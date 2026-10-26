import SwiftUI
import AVFoundation
import HearIAmCore

@MainActor final class FrontDirectionPracticeViewModel: ObservableObject {
    @Published private(set) var practice = FrontDirectionPractice()
    @Published private(set) var isRunning = false
    @Published private(set) var canSetReference = false
    @Published private(set) var issue: String?
    let signals = SignalPlayer()
    let voice = GuidanceSpeech()
    private let sensor: FrontDirectionSensing
    private let now: () -> TimeInterval
    private var latestHeading: Double?
    private var lastSampleTime: TimeInterval?
    private var startedAt: TimeInterval = 0
    private var pendingSide = false
    private var watchdog: Task<Void, Never>?
    private var completionTask: Task<Void, Never>?
    private var generation = UUID()
    private var observers: [NSObjectProtocol] = []

    init(sensor: FrontDirectionSensing? = nil, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.sensor = sensor ?? FrontDirectionSensor()
        self.now = now
        self.sensor.onSample = { [weak self] in self?.receive(heading: $0, time: $1) }
        self.sensor.onFailure = { [weak self] in self?.suspend($0) }
        signals.onEvent = { [weak self] event, _ in
            if event == "signal_error" { self?.suspend("소리를 재생하지 못했어요. 출력 기기를 확인한 뒤 다시 시도해주세요.") }
        }
        voice.onSpeaking = { [weak self] in self?.signals.setSpeechActive($0) }
        voice.onError = { [weak self] _ in self?.suspend("음성이 중단됐어요. 소리 출력을 확인한 뒤 다시 시도해주세요.") }
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.suspend("소리 재생이 중단됐어요. 다시 시작해서 정면을 지정해주세요.")
                HearAudioSession.interrupted()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            guard reason == .oldDeviceUnavailable || reason == .newDeviceAvailable else { return }
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.suspend("출력 기기가 바뀌었어요. 다시 시작해서 정면을 지정해주세요.")
            }
        })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver); watchdog?.cancel(); completionTask?.cancel() }

    func start() {
        guard !isRunning else { return }
        clearSounds()
        practice = FrontDirectionPractice(deadbandDegrees: SignalPlayer.directionDeadbandDegrees)
        issue = nil; latestHeading = nil; lastSampleTime = nil; canSetReference = false
        isRunning = true; startedAt = now()
        sensor.start()
        guard isRunning else { return } // Unsupported hardware may fail synchronously.
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                guard let self, self.isRunning else { return }
                self.checkFreshness()
            }
        }
    }
    func checkFreshness() {
        guard isRunning else { return }
        let elapsed = now() - (lastSampleTime ?? startedAt)
        if elapsed > (lastSampleTime == nil ? 3 : 1.5) {
            suspend("몸 방향 정보가 끊겼어요. 다시 시작해서 정면을 지정해주세요.")
        }
    }
    func close() { suspend(nil) }
    func suspend(_ message: String?) {
        isRunning = false; sensor.stop(); watchdog?.cancel(); watchdog = nil
        latestHeading = nil; lastSampleTime = nil; canSetReference = false
        practice.reset(); clearSounds(); signals.shutdown(); voice.deactivate(); issue = message
    }
    func setReference() {
        guard isRunning, canSetReference, let heading = latestHeading, let time = lastSampleTime else { return }
        guard now() - time <= 0.5 else {
            suspend("몸 방향 정보를 다시 확인해야 해요. 다시 시작해서 정면을 지정해주세요."); return
        }
        guard prepareOutput() else { return }
        clearSounds(); issue = nil
        practice.setReference(heading)
        voice.play(["정면을 지정했어요. 제자리에서 몸을 왼쪽이나 오른쪽으로 조금 돌린 뒤, 소리를 따라 돌아와보세요."])
    }
    func repeatExercise() {
        guard isRunning, practice.referenceHeading != nil, prepareOutput() else { return }
        clearSounds(); practice.repeatExercise()
        voice.play(["같은 정면으로 다시 연습해요. 제자리에서 몸을 조금 돌린 뒤, 소리를 따라 돌아와보세요."])
    }
    func resetReference() {
        clearSounds(); practice.reset(); issue = nil
        voice.play(["몸을 정면으로 향한 뒤, 이 방향을 정면으로 지정 버튼을 눌러주세요."])
    }
    private func prepareOutput() -> Bool {
        do { try HearAudioSession.activate() }
        catch { suspend("소리를 재생하지 못했어요. 출력 기기를 확인한 뒤 다시 시도해주세요."); return false }
        guard AVAudioSession.sharedInstance().outputVolume > 0 else {
            suspend("소리가 꺼져 있어요. iPhone의 음량을 올린 뒤 다시 시작해주세요."); return false
        }
        return true
    }
    private func clearSounds() {
        generation = UUID(); completionTask?.cancel(); completionTask = nil; pendingSide = false
        signals.stop(); voice.stop()
    }
    private func receive(heading: Double?, time: TimeInterval) {
        guard isRunning else { return }
        guard time.isFinite, now() - time >= -0.1, now() - time <= 0.5,
              lastSampleTime.map({ time > $0 }) ?? true else {
            suspend("몸 방향 정보를 다시 확인해야 해요. 다시 시작해서 정면을 지정해주세요."); return
        }
        lastSampleTime = time
        guard let heading, heading.isFinite else {
            let hadReference = practice.referenceHeading != nil
            let firstInvalidSample = latestHeading != nil || issue == nil
            latestHeading = nil; canSetReference = false
            practice.reset()
            if firstInvalidSample { clearSounds() }
            issue = "휴대폰을 세워 몸에 고정해주세요. 자세를 잡은 뒤 정면을 다시 지정해요."
            if hadReference { voice.play(["휴대폰을 세워 몸에 고정한 뒤 정면을 다시 지정해주세요."]) }
            return
        }
        latestHeading = heading; canSetReference = true; issue = nil
        let previousPhase = practice.phase
        let cue = practice.update(heading: heading, time: time)
        if practice.phase == .completed, previousPhase != .completed {
            complete(); return
        }
        guard let cue else { return }
        if cue.spokenWord != nil { pendingSide = true }
        if pendingSide {
            guard !voice.isSpeaking || voice.speakingDirection else { return }
            signals.stopDirection()
            pendingSide = !voice.direction(cue.word, volume: SignalVolume.speech, interrupting: true)
        } else if !voice.isSpeaking, cue.shouldTick {
            signals.play(.directionTick(toRight: cue.toRight))
        }
    }
    private func complete() {
        clearSounds()
        let token = generation
        let sound = SignalSound.aligned(tone: SignalPlayer.savedAlignedTone)
        signals.play(sound)
        guard generation == token, practice.phase == .completed else { return }
        let duration = Double(ToneRenderer.render(sound).count) / ToneRenderer.sampleRate
        completionTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64((duration + 0.1) * 1e9)) } catch { return }
            guard let self, self.generation == token, self.isRunning, self.practice.phase == .completed else { return }
            self.voice.play(["방향이 맞았어요. 지정한 정면으로 돌아왔어요."])
        }
    }
}
