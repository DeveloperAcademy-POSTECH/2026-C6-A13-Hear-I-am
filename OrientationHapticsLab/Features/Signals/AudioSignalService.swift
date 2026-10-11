import AVFoundation
import Combine
import UIKit

@MainActor
final class AudioSignalService: NSObject, SignalOutput {
    @Published private(set) var state: SignalPlaybackState
    var statePublisher: AnyPublisher<SignalPlaybackState, Never> { $state.eraseToAnyPublisher() }
    private let mode: SignalMode
    private var speechStyle: SpeechStyle = .angle
    private var synthesizer: AVSpeechSynthesizer?
    private var utteranceID: ObjectIdentifier?
    private var player: AVAudioPlayer?
    private var timeout: Task<Void, Never>?
    private var generation = 0
    private var sessionActive = false
    private var subscriptions = Set<AnyCancellable>()
    private var waveCache: [AudioCueKey: Data] = [:]

    private enum AudioCueKey: Hashable { case angle(Int), reset }

    init(mode: SignalMode) {
        precondition(mode == .speech || mode == .beep)
        self.mode = mode
        state = .init(status: "\(mode.title) 준비됨")
        super.init()
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in self?.stop() }
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { @Sendable [weak self] notification in
                let began = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                    == AVAudioSession.InterruptionType.began.rawValue
                if began {
                    Task { @MainActor [weak self] in
                        self?.interrupt(message: "시스템이 소리를 중단했어요. 다음 신호에서 다시 준비합니다.")
                    }
                }
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { @Sendable [weak self] notification in
                let disconnected = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                    == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                if disconnected {
                    Task { @MainActor [weak self] in
                        self?.interrupt(message: "소리 출력 기기가 연결 해제됐어요. 다음 신호에서 다시 준비합니다.")
                    }
                }
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .sink { @Sendable [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.interrupt(message: "소리 서비스를 다시 준비합니다.")
                    self?.synthesizer = nil
                }
            }.store(in: &subscriptions)
    }

    func setSpeechStyle(_ style: SpeechStyle) {
        guard speechStyle != style else { return }
        stop()
        speechStyle = style
    }

    func prepare() {
        guard state.label == nil else { return }
        state = .init(status: "\(mode.title) 준비됨")
    }

    @discardableResult
    func playAngle(_ signedDegrees: Double, configuration: HapticConfiguration? = nil) -> Bool {
        guard let cue = AudioCue.angle(signedDegrees, speechStyle: speechStyle) else {
            stop()
            state = .init(status: "소리 각도 설정 오류", error: "정면과 뒤쪽을 포함한 30° 간격의 방향만 지원합니다.")
            return false
        }
        return play(cue, key: .angle(Int(signedDegrees.rounded())), angle: signedDegrees)
    }

    @discardableResult
    func playReset() -> Bool { play(.reset(style: speechStyle), key: .reset, angle: nil) }

    func stop() {
        generation &+= 1
        timeout?.cancel()
        timeout = nil
        // Clear identities before stopping: a queued cancellation must not clear the next signal.
        utteranceID = nil
        synthesizer?.stopSpeaking(at: .immediate)
        player?.stop()
        player = nil
        releaseSession()
        state = .init(status: "\(mode.title) 중지됨")
    }

    private func play(_ cue: AudioCue, key: AudioCueKey, angle: Double?) -> Bool {
        stop()
        guard UIApplication.shared.applicationState == .active else {
            state = .init(status: "소리 보류 · 앱을 화면에 열어 주세요")
            return false
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)
            sessionActive = true
            guard session.outputVolume > 0 else {
                stop()
                state = .init(status: "소리 음량이 0이에요", error: "아이폰의 미디어 음량을 올려 주세요.")
                return false
            }
            if mode == .speech {
                guard let voice = AVSpeechSynthesisVoice(language: "ko-KR") else {
                    stop()
                    state = .init(status: "한국어 음성 준비 실패", error: "기기에서 한국어 음성을 사용할 수 없어요.")
                    return false
                }
                if synthesizer == nil {
                    synthesizer = AVSpeechSynthesizer()
                    synthesizer?.usesApplicationAudioSession = true
                    synthesizer?.delegate = self
                }
                let utterance = AVSpeechUtterance(string: cue.speech)
                utterance.voice = voice
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate
                utteranceID = ObjectIdentifier(utterance)
                synthesizer?.speak(utterance)
            } else {
                let data = waveCache[key] ?? cue.waveData()
                waveCache[key] = data
                let nextPlayer = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
                nextPlayer.delegate = self
                player = nextPlayer
                guard nextPlayer.prepareToPlay(), nextPlayer.play() else {
                    stop()
                    state = .init(status: "비프음 재생 실패", error: "소리를 재생하지 못했어요. 다시 체험해 주세요.")
                    return false
                }
            }
            state = .init(label: angle == nil ? "기준 방향 리셋" : cue.speech,
                          angle: angle, status: "\(mode.title) 재생 중")
            let token = generation
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.stop()
                self.state = .init(status: "소리 재생 시간 초과", error: "소리 재생을 완료하지 못했어요. 다시 체험해 주세요.")
            }
            return true
        } catch {
            stop()
            state = .init(status: "\(mode.title) 준비 실패", error: error.localizedDescription)
            return false
        }
    }

    private func interrupt(message: String) {
        guard sessionActive else { return }
        stop()
        state = .init(status: message)
    }

    private func finish(utterance: ObjectIdentifier? = nil, playerID: ObjectIdentifier? = nil, error: String? = nil) {
        if let utterance { guard utterance == utteranceID else { return } }
        if let playerID { guard player.map(ObjectIdentifier.init) == playerID else { return } }
        timeout?.cancel()
        timeout = nil
        utteranceID = nil
        player = nil
        releaseSession()
        state = .init(status: error == nil ? "\(mode.title) 준비됨" : "\(mode.title) 재생 실패", error: error)
    }

    private func releaseSession() {
        guard sessionActive else { return }
        sessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension AudioSignalService: AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finish(utterance: id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finish(utterance: id) }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            self?.finish(playerID: id, error: flag ? nil : "소리 재생이 중단됐어요.")
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let id = ObjectIdentifier(player)
        let message = error?.localizedDescription ?? "소리를 읽지 못했어요."
        Task { @MainActor [weak self] in self?.finish(playerID: id, error: message) }
    }
}
