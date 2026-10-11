import AVFoundation
import Combine
import UIKit

@MainActor
final class SpeakerGuide: ObservableObject {
    @Published var speechStyle = DirectionSpeechStyle(rawValue: UserDefaults.standard.string(forKey: "PoC3.speechStyle") ?? "") ?? .angle {
        didSet {
            UserDefaults.standard.set(speechStyle.rawValue, forKey: "PoC3.speechStyle")
            stop()
        }
    }
    @Published var outputMode = AudioOutputMode(rawValue: UserDefaults.standard.string(forKey: "PoC3.outputMode") ?? "") ?? .speaker {
        didSet {
            guard outputMode != oldValue else { return }
            UserDefaults.standard.set(outputMode.rawValue, forKey: "PoC3.outputMode")
            unavailable("출력 변경 · 소리를 확인한 뒤 안내를 다시 시작하세요")
            do { try configureSession() }
            catch { status = "출력 설정 실패: \(error.localizedDescription)" }
            refreshRoute()
        }
    }
    @Published private(set) var routeName = "출력 기기 확인 전"
    private var preparedIDs: Set<String>?
    @Published private(set) var ready = false
    @Published private(set) var status = "음성 출력 준비 필요"
    @Published private(set) var lastSpoken = ""
    var onUnavailable: (() -> Void)?
    private let synthesizer = AVSpeechSynthesizer()
    private var subscriptions = Set<AnyCancellable>()
    private var lastKind: BodyInstruction.Kind?
    private var lastTime = -Double.infinity
    private var voice: AVSpeechSynthesisVoice?

    init() {
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      raw == AVAudioSession.InterruptionType.began.rawValue else { return }
                Task { @MainActor [weak self] in self?.unavailable("오디오 중단 · 소리를 다시 준비하세요") }
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] note in
                let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.refreshRoute()
                    if self.ready && reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                        self.unavailable("출력 기기 연결 해제 · 소리를 다시 확인하세요")
                    } else { self.validateOutput() }
                }
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.unavailable("오디오 재설정 · 소리를 다시 준비하세요") }
            }.store(in: &subscriptions)
    }
    private var ports: [GuidanceAudioPort] {
        AVAudioSession.sharedInstance().currentRoute.outputs.map { port in
            let kind: GuidanceAudioPort.Kind
            switch port.portType {
            case .builtInSpeaker: kind = .speaker
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: kind = .bluetooth
            default: kind = .other
            }
            return GuidanceAudioPort(id: port.uid, kind: kind)
        }
    }
    private func refreshRoute() {
        let names = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portName)
        routeName = names.isEmpty ? "연결된 출력 없음" : names.joined(separator: ", ")
    }
    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        if session.category == .playAndRecord { try session.overrideOutputAudioPort(.none) }
        if outputMode == .speaker {
            // No recording occurs. This category is required by Apple's speaker override API.
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            try session.overrideOutputAudioPort(.speaker)
        } else {
            // Playback supports Bluetooth A2DP; the user selects the device in the system route picker.
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        }
    }
    func prepare() {
        stop(); ready = false; preparedIDs = nil
        do {
            try configureSession()
            refreshRoute()
            let session = AVAudioSession.sharedInstance()
            voice = AVSpeechSynthesisVoice(language: "ko-KR")
            guard AudioOutputPolicy.accepts(ports, mode: outputMode) else {
                unavailable(outputMode == .airPods
                    ? "에어팟을 이 폰에 연결하고 아래 출력 기기 버튼에서 선택한 뒤 다시 준비하세요"
                    : "폰 스피커 출력을 확인한 뒤 다시 준비하세요")
                return
            }
            guard voice != nil, session.outputVolume > 0 else {
                unavailable("미디어 음량과 한국어 음성을 확인하세요"); return
            }
            preparedIDs = Set(ports.map(\.id))
            ready = true; status = "\(outputMode.title) · 한국어 음성 준비됨"
            announce("\(outputMode.title) 안내가 준비되었습니다")
        } catch { unavailable("소리 준비 실패: \(error.localizedDescription)") }
    }
    func validateOutput() {
        guard ready else { return }
        if !AudioOutputPolicy.accepts(ports, mode: outputMode, preparedIDs: preparedIDs)
            || AVAudioSession.sharedInstance().outputVolume <= 0 {
            unavailable("출력 기기 또는 음량 변경 · 소리를 확인한 뒤 안내를 다시 시작하세요")
        }
    }
    func update(_ instruction: BodyInstruction, now: Double) {
        guard ready else { return }
        let changed = lastKind != instruction.kind
        // Replace opposite/stop instructions immediately. Do not queue a backlog.
        guard changed || now - lastTime >= 3 else { return }
        if !changed && synthesizer.isSpeaking { return }
        lastKind = instruction.kind; lastTime = now
        announce(instruction.spoken(style: speechStyle))
    }
    func announce(_ text: String) {
        validateOutput()
        guard ready else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice; utterance.rate = 0.48
        lastSpoken = text
        synthesizer.speak(utterance)
    }
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        lastKind = nil; lastTime = -.infinity
    }
    private func unavailable(_ reason: String) {
        stop(); ready = false; preparedIDs = nil; status = reason; onUnavailable?()
    }
    func shutdown() {
        stop(); ready = false; preparedIDs = nil; status = "음성 출력 준비 필요"
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
