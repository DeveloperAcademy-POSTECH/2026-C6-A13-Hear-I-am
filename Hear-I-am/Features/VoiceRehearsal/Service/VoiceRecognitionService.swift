import AVFoundation
import Accelerate
import Combine
import Speech
import UIKit
import OSLog
import HearIAmCore

/// An on-device, Korean command listener for the voice rehearsal experiment.
/// The caller owns when listening is allowed; stop() releases microphone capture completely.
@MainActor final class VoiceRecognitionService: NSObject, ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isAvailable = false
    @Published private(set) var isRecovering = false
    @Published private(set) var transcript = ""
    @Published private(set) var statusMessage = "음성 입력이 꺼져 있어요"

    var onSpeechDetected: (() -> Void)?
    var onTranscript: ((String) -> Void)?
    /// Only a final recognizer result reaches this callback, once per recognition turn.
    var onFinal: ((String) -> Void)?
    /// Transient failures pause a command, but keep the microphone session eligible for recovery.
    var onRecoverableError: ((String) -> Void)?
    var onRecoveryReady: (() -> Void)?
    var onError: ((String) -> Void)?

    // Meter updates go directly to the waveform, not through the AR view model's objectWillChange.
    let inputVisualization = VoiceInputVisualization()

    private var engine: AVAudioEngine?
    private var hasInputTap = false
    private var engineID: UUID?
    private var restartAudioNeeded = false
    private var retryScheduled = false
    private var recoveryReadyPending = false
    private var turnInputConfirmed = false
    private var turnStartedAt: Double = 0
    private var configurationTimer: Task<Void, Never>?
    private var microphoneTimer: Task<Void, Never>?
    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var taskDelegate: VoiceRecognitionTaskDelegate?
    private let inputBridge = VoiceRecognitionInputBridge()
    private let narration = VoiceNarrationPlayer()
    private var inputLease: UUID?
    private var sessionID: UUID?
    private var turnID: UUID?
    private var wantsListening = false
    private var speechDetected = false
    private var finalizing = false
    private var contextualStrings: [String] = []
    private var recovery = VoiceInputRecoveryPolicy()
    private let logger = Logger(subsystem: "org.heariam.poc4.scanlab", category: "VoiceInput")
    private var observers: [NSObjectProtocol] = []
    private var restartTimer: Task<Void, Never>?
    private var taskLimitTimer: Task<Void, Never>?
    private var speechLimitTimer: Task<Void, Never>?
    private var endpointTimer: Task<Void, Never>?
    private var finalResultTimer: Task<Void, Never>?

    override init() {
        super.init()
        narration.onEngineUnavailable = { [weak self] in
            self?.recover("오디오 연결을 다시 준비하고 있어요", restartAudio: true, source: "narration_engine_stopped")
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil) { [weak self] notification in
            guard let changed = notification.object as? AVAudioEngine else { return }
            let identity = ObjectIdentifier(changed)
            // Never tear down an engine on its own notification/render thread.
            Task { @MainActor [weak self] in
                guard let self, let engine = self.engine, ObjectIdentifier(engine) == identity else { return }
                self.engineConfigurationChanged(engine)
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor [weak self] in
                self?.stopForExternalChange("다른 소리가 시작되어 음성 입력을 멈췄어요. 다시 듣기를 눌러주세요.", restorePlayback: false)
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard let raw, let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                  [.newDeviceAvailable, .oldDeviceUnavailable, .noSuitableRouteForCategory, .override].contains(reason) else { return }
            Task { @MainActor [weak self] in
                self?.stopForExternalChange("마이크 연결이 바뀌었어요. 연결을 확인하고 다시 듣기를 눌러주세요.")
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopForExternalChange("화면을 벗어나 음성 입력을 멈췄어요. 다시 듣기를 눌러주세요.", restorePlayback: false)
            }
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        restartTimer?.cancel()
        configurationTimer?.cancel()
        microphoneTimer?.cancel()
        taskLimitTimer?.cancel()
        speechLimitTimer?.cancel()
        endpointTimer?.cancel()
        finalResultTimer?.cancel()
        inputBridge.clear()
        recognitionTask?.cancel()
        engine?.stop()
        if let inputLease {
            Task { @MainActor in HearAudioSession.releaseVoiceInput(inputLease) }
        }
    }

    /// This PoC never silently falls back to server recognition.
    /// Permission/availability failures leave microphone capture off and explain the reason.
    func start(contextualStrings: [String] = []) async {
        stop()
        let identifier = UUID()
        sessionID = identifier
        statusMessage = "마이크와 음성 인식을 준비하고 있어요"
        let microphoneAllowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard sessionID == identifier else { return }
        guard microphoneAllowed else {
            failPermanently("마이크 권한이 필요해요. 설정에서 마이크 접근을 허용해주세요.")
            return
        }
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard sessionID == identifier else { return }
        guard authorization == .authorized else {
            failPermanently("음성 인식 권한이 필요해요. 설정에서 음성 인식을 허용해주세요.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR")), recognizer.isAvailable else {
            failPermanently("이 기기에서 한국어 음성 인식을 사용할 수 없어요. 버튼으로 진행해주세요.")
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            failPermanently("이 기기는 기기 내 한국어 인식을 사용할 수 없어요. 이번 실험은 음성을 서버로 전송하지 않아요.")
            return
        }
        self.recognizer = recognizer
        self.contextualStrings = Array(contextualStrings.filter { !$0.isEmpty }.prefix(100))
        do {
            inputLease = try HearAudioSession.acquireVoiceInput()
            wantsListening = true
            isAvailable = true
            recovery.reset()
            beginTurn()
        } catch {
            trace("Voice input session failed: \(String(describing: error))", level: .error)
            failPermanently("마이크를 준비할 수 없어요. 버튼으로 진행하거나 다시 듣기를 눌러주세요.")
        }
    }

    /// Voice processing is enabled once per listening session. Configuration changes restart this
    /// same engine; destroying VPIO during recovery would itself trigger another route change.
    private func prepareEngine() throws {
        let engine: AVAudioEngine
        if let existing = self.engine {
            engine = existing
        } else {
            engine = AVAudioEngine()
            self.engine = engine
            let identifier = UUID()
            engineID = identifier
            trace("voice_engine_created id=\(identifier.uuidString)")
            try engine.inputNode.setVoiceProcessingEnabled(true)
            narration.attach(to: engine)
        }
        guard engine.inputNode.isVoiceProcessingEnabled else { throw VoiceRecognitionFailure.noInput }
        guard restartAudioNeeded || !engine.isRunning else { return }
        engine.stop()
        if hasInputTap { engine.inputNode.removeTap(onBus: 0); hasInputTap = false }
        // VPIO requires matching capture/output client formats. A lazily created mixer may
        // still expose its default 44.1 kHz stereo output even when capture is 48 kHz mono.
        // Reconnect only while stopped, using this route's current capture format (not fixed 48k).
        // The TTS player stays connected at 48k; the mixer performs any output conversion.
        let hardwareInput = engine.inputNode.inputFormat(forBus: 0)
        let hardwareOutput = engine.outputNode.outputFormat(forBus: 0)
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard hardwareInput.sampleRate.isFinite, hardwareInput.sampleRate > 0, hardwareInput.channelCount > 0,
              hardwareOutput.sampleRate.isFinite, hardwareOutput.sampleRate > 0, hardwareOutput.channelCount > 0,
              format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0 else {
            throw VoiceRecognitionFailure.noInput
        }
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
        let output = engine.outputNode.inputFormat(forBus: 0)
        trace("voice_engine_start id=\(self.engineID?.uuidString ?? "none") hardwareInput=\(hardwareInput.description) input=\(format.description) output=\(output.description) route=\(HearAudioSession.route)")
        guard output.sampleRate == format.sampleRate, output.channelCount == format.channelCount else {
            throw VoiceRecognitionFailure.noInput
        }
        let bridge = inputBridge
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            bridge.append(buffer)
        }
        hasInputTap = true
        engine.prepare()
        try engine.start()
        restartAudioNeeded = false
    }

    private func engineConfigurationChanged(_ changed: AVAudioEngine) {
        guard wantsListening else { return }
        trace("voice_engine_configuration id=\(self.engineID?.uuidString ?? "none") running=\(changed.isRunning) route=\(HearAudioSession.route)")
        // A notification queued while enabling VPIO can arrive after start() has succeeded.
        // Running engines are checked by the input watchdog instead of rebuilt on notification.
        guard !changed.isRunning else { return }
        inputVisualization.reset()
        isListening = false
        guard !retryScheduled, configurationTimer == nil else { return }
        // Reject a final result queued before the device stopped, even during debounce.
        retireTurn()
        let session = sessionID
        configurationTimer = Task { @MainActor [weak self, weak changed] in
            do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
            guard let self else { return }
            self.configurationTimer = nil
            guard self.wantsListening, self.sessionID == session,
                  let changed, self.engine === changed else { return }
            if changed.isRunning { self.beginTurn(); return }
            self.recover("오디오 연결을 다시 준비하고 있어요", restartAudio: true, source: "engine_configuration")
        }
    }

    private func microphoneReady(turnID: UUID) {
        guard wantsListening, self.turnID == turnID, !finalizing, !retryScheduled,
              engine?.isRunning == true, inputBridge.isReady,
              !inputBridge.isStalled(at: ProcessInfo.processInfo.systemUptime) else { return }
        turnInputConfirmed = true
        trace("voice_input_ready engine=\(self.engineID?.uuidString ?? "none") turn=\(turnID.uuidString) route=\(HearAudioSession.route)")
        isRecovering = false
        if recoveryReadyPending {
            recoveryReadyPending = false
            onRecoveryReady?()
        }
        guard wantsListening, self.turnID == turnID else { return }
        statusMessage = "말씀하시면 들을게요"
        // The UI and ready chime subscribe to this value. Task creation is not microphone readiness.
        isListening = true
    }

    private func watchMicrophone(turnID: UUID) {
        microphoneTimer?.cancel()
        microphoneTimer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
                guard let self, self.wantsListening, self.turnID == turnID, !self.finalizing else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let timedOut = !self.turnInputConfirmed && now - self.turnStartedAt >= 4
                if timedOut || self.inputBridge.isStalled(at: now) {
                    self.recover("마이크 입력을 다시 확인하고 있어요", restartAudio: true, source: timedOut ? "first_buffer_timeout" : "input_stalled")
                    return
                }
            }
        }
    }

    /// Cancels all delayed rearming as well as the current recognition task and microphone tap.
    func stop() {
        stopCapture(restorePlayback: true)
        transcript = ""
        statusMessage = "음성 입력이 꺼져 있어요"
    }

    /// Render narration through the same voice-processing engine as microphone capture.
    func speakNarration(_ utterance: AVSpeechUtterance, completion: @escaping (Bool) -> Void) -> Bool {
        guard wantsListening, let engine, engine.isRunning else { return false }
        narration.speak(utterance, completion: completion)
        return true
    }
    func stopNarration() { narration.stop() }

    /// Touch/back actions invalidate speech recorded for the previous choice screen.
    func discardPendingSpeech() {
        guard wantsListening else { return }
        guard !isRecovering else { return }
        retireTurn(); isListening=false
        scheduleNextTurn(after: 0.05)
    }

    private func beginTurn() {
        guard wantsListening else { return }
        retryScheduled = false
        guard let recognizer, recognizer.isAvailable else {
            recover("음성 인식을 다시 연결하고 있어요", restartAudio: false, source: "recognizer_unavailable")
            return
        }
        do {
            try prepareEngine()
            guard engine?.isRunning == true else {
                recover("오디오 연결을 다시 준비하고 있어요", restartAudio: true, source: "engine_start_stopped")
                return
            }
        } catch {
            trace("Voice engine start failed: \(String(describing: error))", level: .error)
            recover("마이크를 다시 연결하고 있어요", restartAudio: true, source: "engine_start_failed")
            return
        }
        guard wantsListening else { return }
        retireTurn()
        let identifier = UUID()
        turnID = identifier
        turnStartedAt = ProcessInfo.processInfo.systemUptime
        turnInputConfirmed = false
        isListening = false
        speechDetected = false
        finalizing = false
        transcript = ""
        statusMessage = "마이크 입력을 확인하고 있어요"
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.contextualStrings = contextualStrings
        request.addsPunctuation = false
        let delegate = VoiceRecognitionTaskDelegate(service: self, turnID: identifier)
        taskDelegate = delegate
        recognitionTask = recognizer.recognitionTask(with: request, delegate: delegate)
        inputBridge.replace(with: request, onReady: { [weak self] in
            Task { @MainActor [weak self] in self?.microphoneReady(turnID: identifier) }
        }, onLevel: { [weak self] level in
            Task { @MainActor [weak self] in
                guard let self, self.wantsListening, self.turnID == identifier,
                      self.isListening, !self.finalizing, self.engine?.isRunning == true else { return }
                self.inputVisualization.update(level)
            }
        })
        watchMicrophone(turnID: identifier)
        // The older Speech API is not a forever-listening task. Rotate idle tasks below its one-minute
        // documented limit. Once speech starts, its own short utterance deadline takes over.
        taskLimitTimer = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 48_000_000_000) } catch { return }
            guard let self, self.turnID == identifier else { return }
            if self.speechDetected { self.finishInput(turnID: identifier) }
            else {
                self.retireTurn()
                self.scheduleNextTurn(after: 0.3)
            }
        }
    }

    fileprivate func detectedSpeech(turnID: UUID) {
        guard self.turnID == turnID, wantsListening, turnInputConfirmed, engine?.isRunning == true, !speechDetected, !finalizing else { return }
        speechDetected = true
        statusMessage = "듣고 있어요"
        speechLimitTimer = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 12_000_000_000) } catch { return }
            self?.finishInput(turnID: turnID)
        }
        onSpeechDetected?()
    }

    fileprivate func receivedPartial(_ text: String, turnID: UUID) {
        guard self.turnID == turnID, wantsListening, turnInputConfirmed, engine?.isRunning == true, !finalizing else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Some recognizer routes provide text before the optional detection delegate callback.
        detectedSpeech(turnID: turnID)
        guard self.turnID == turnID else { return }
        transcript = text
        statusMessage = "듣고 있어요"
        onTranscript?(text)
        endpointTimer?.cancel()
        endpointTimer = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 1_100_000_000) } catch { return }
            self?.finishInput(turnID: turnID)
        }
    }

    private func finishInput(turnID: UUID) {
        guard self.turnID == turnID, wantsListening, !finalizing else { return }
        finalizing = true
        inputVisualization.reset()
        microphoneTimer?.cancel(); microphoneTimer = nil
        isListening = false
        statusMessage = "말씀을 확인하고 있어요"
        endpointTimer?.cancel()
        speechLimitTimer?.cancel()
        taskLimitTimer?.cancel()
        inputBridge.finish()
        recognitionTask?.finish()
        finalResultTimer = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            guard let self, self.turnID == turnID else { return }
            self.recognitionFailed("말씀을 끝까지 확인하지 못했어요. 다시 말씀해주세요.", turnID: turnID)
        }
    }

    fileprivate func receivedFinal(_ text: String, turnID: UUID) {
        guard self.turnID == turnID, wantsListening else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { detectedSpeech(turnID: turnID) }
        guard self.turnID == turnID, wantsListening else { return }
        if text.isEmpty {
            rearmAfterSilence(discardCommand: speechDetected)
            return
        }
        guard turnInputConfirmed else {
            recover("마이크 입력을 다시 확인하고 있어요", restartAudio: false, source: "result_before_input")
            return
        }
        retireTurn()
        recovery.recordFinalRecognition(text)
        transcript = text
        isListening = false
        statusMessage = "말씀을 확인했어요"
        // turnID is invalidated before calling application code so duplicate final callbacks and
        // a cancellation delivered afterward can never execute the command a second time.
        onFinal?(text)
        if wantsListening { scheduleNextTurn(after: 0.05) }
    }

    fileprivate func taskFinished(successfully: Bool, errorCode: Int?, errorDomain: String?, turnID: UUID) {
        guard self.turnID == turnID else { return }
        if successfully {
            // Delegate callbacks cross onto MainActor separately. Give an already-dispatched final
            // result a chance to arrive instead of invalidating it from this completion callback.
            // The finish event itself carries no final transcript; never promote a partial result.
            finalResultTimer?.cancel()
            finalResultTimer = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
                guard let self, self.turnID == turnID else { return }
                if self.speechDetected {
                    self.recognitionFailed("말씀을 끝까지 확인하지 못했어요. 다시 말씀해주세요.", turnID: turnID)
                } else {
                    self.rearmAfterSilence()
                }
            }
        } else if errorDomain == "kAFAssistantErrorDomain", errorCode == 1110, !speechDetected {
            // No-speech is an ordinary end of an idle ASR task, not a disconnected microphone.
            rearmAfterSilence()
        } else {
            trace("Recognition task failed: domain=\(errorDomain ?? "none") code=\(errorCode ?? 0)", level: .error)
            recognitionFailed("음성을 확인하지 못했어요. 다시 들을게요.", turnID: turnID)
        }
    }

    private func rearmAfterSilence(discardCommand: Bool = false) {
        // An immediate empty/no-speech result is not proof of a healthy microphone. Bound those
        // retries too, while allowing ordinary long idle recognition turns to rotate silently.
        guard turnInputConfirmed, ProcessInfo.processInfo.systemUptime - turnStartedAt >= 2 else {
            recover("음성 입력을 다시 확인하고 있어요", restartAudio: engine?.isRunning != true, source: "premature_empty_result")
            return
        }
        retireTurn()
        isListening = false
        statusMessage = "말씀하시면 다시 들을게요"
        // Idle/no-speech rollover must not pause an otherwise healthy walking session.
        if discardCommand { onRecoverableError?(statusMessage) }
        scheduleNextTurn(after: 0.5)
    }

    private func recognitionFailed(_ message: String, turnID: UUID) {
        guard self.turnID == turnID, wantsListening else { return }
        recover(message, restartAudio: engine?.isRunning != true, source: "recognition_failed")
    }

    private func recover(_ message: String, restartAudio: Bool, source: String) {
        guard wantsListening, !retryScheduled else { return }
        guard let delay = recovery.nextDelay() else {
            trace("Voice input recovery exhausted", level: .error)
            failPermanently("음성 입력을 연결하지 못했어요. 버튼으로 진행하거나 다시 듣기를 눌러주세요.")
            return
        }
        retryScheduled = true
        recoveryReadyPending = true
        isRecovering = true
        isListening = false
        configurationTimer?.cancel(); configurationTimer = nil
        retireTurn()
        statusMessage = message
        trace("voice_input_recovery source=\(source) engine=\(self.engineID?.uuidString ?? "none") restartAudio=\(restartAudio) delay=\(delay) route=\(HearAudioSession.route)")
        // The owner first cancels narration and pauses movement. An input failure must never
        // silently continue walking, or turn a partial transcript into a command.
        onRecoverableError?(message)
        guard wantsListening else { return }
        if restartAudio {
            restartAudioNeeded = true
            engine?.stop()
        }
        scheduleNextTurn(after: delay)
    }

    private func scheduleNextTurn(after delay: Double) {
        restartTimer?.cancel()
        guard wantsListening, let sessionID else { return }
        restartTimer = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            guard let self, self.sessionID == sessionID, self.wantsListening else { return }
            self.beginTurn()
        }
    }

    private func retireTurn() {
        inputVisualization.reset()
        isListening = false
        turnID = nil
        turnInputConfirmed = false
        microphoneTimer?.cancel(); microphoneTimer = nil
        taskLimitTimer?.cancel(); taskLimitTimer = nil
        speechLimitTimer?.cancel(); speechLimitTimer = nil
        endpointTimer?.cancel(); endpointTimer = nil
        finalResultTimer?.cancel(); finalResultTimer = nil
        inputBridge.clear()
        recognitionTask?.cancel(); recognitionTask = nil
        taskDelegate = nil
        speechDetected = false
        finalizing = false
    }

    private func stopCapture(restorePlayback: Bool) {
        wantsListening = false
        sessionID = nil
        retryScheduled = false
        recoveryReadyPending = false
        configurationTimer?.cancel(); configurationTimer = nil
        restartTimer?.cancel(); restartTimer = nil
        retireTurn()
        tearDownEngine()
        recognizer = nil
        recovery.reset()
        isRecovering = false
        if let inputLease {
            HearAudioSession.releaseVoiceInput(inputLease, restorePlayback: restorePlayback)
        }
        inputLease = nil
        isListening = false
        isAvailable = false
    }

    private func tearDownEngine() {
        // Called only when capture is explicitly stopped, never by automatic recovery.
        if let engineID { trace("voice_engine_destroyed id=\(engineID.uuidString)") }
        engine?.stop()
        narration.detach()
        if let engine {
            engine.stop()
            if hasInputTap { engine.inputNode.removeTap(onBus: 0) }
            engine.reset()
        }
        engine = nil
        engineID = nil
        restartAudioNeeded = false
        hasInputTap = false
    }

    /// Device validation without LLDB can opt into the same metadata on stderr. No transcript
    /// or microphone samples are emitted. Release builds keep only the ordinary OSLog events.
    private func trace(_ message: String, level: OSLogType = .default) {
        logger.log(level: level, "\(message, privacy: .public)")
        #if DEBUG
        if ProcessInfo.processInfo.environment["HEAR_VOICE_DIAGNOSTICS"] == "1" {
            let line = "[VoiceInput \(ProcessInfo.processInfo.systemUptime)] \(message)\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
        #endif
    }

    private func failPermanently(_ message: String) {
        stopCapture(restorePlayback: true)
        statusMessage = message
        onError?(message)
    }

    private func stopForExternalChange(_ message: String, restorePlayback: Bool = true) {
        guard wantsListening else { return }
        stopCapture(restorePlayback: restorePlayback)
        statusMessage = message
        onError?(message)
    }
}

/// Separate observable state keeps microphone metering local to the decorative waveform.
@MainActor final class VoiceInputVisualization: ObservableObject {
    @Published private(set) var level: Double = 0
    func update(_ value: Double) { level = min(1, max(0, value.isFinite ? value : 0)) }
    func reset() { if level != 0 { level = 0 } }
}

private enum VoiceRecognitionFailure: Error { case noInput }

/// AVAudioEngine's tap runs off the main actor. Append directly while the tap's buffer is valid;
/// this small lock also keeps endAudio/cancel from racing an in-flight append.
private final class VoiceRecognitionInputBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var readiness = VoiceMicrophoneReadiness()
    private var onReady: (@Sendable () -> Void)?
    private var onLevel: (@Sendable (Double) -> Void)?
    private var levelMeter = VoiceInputLevelMeter()

    var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return readiness.isReady
    }
    func isStalled(at time: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return readiness.isStalled(at: time)
    }
    func replace(with request: SFSpeechAudioBufferRecognitionRequest,
                 onReady: @escaping @Sendable () -> Void, onLevel: @escaping @Sendable (Double) -> Void) {
        lock.lock(); defer { lock.unlock() }
        self.request = request
        self.onReady = onReady
        self.onLevel = onLevel
        readiness.reset()
        levelMeter.reset()
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0, buffer.format.sampleRate.isFinite,
              buffer.format.sampleRate > 0, buffer.format.channelCount > 0 else { return }
        lock.lock()
        guard let request else { lock.unlock(); return }
        request.append(buffer)
        // Read the already captured, echo-processed PCM. No second engine or tap is installed.
        let rms = Self.rootMeanSquare(buffer)
        let visualLevel = levelMeter.ingest(rms: rms, at: ProcessInfo.processInfo.systemUptime)
        let levelCallback = onLevel
        let becameReady = readiness.ingest(frameCount: Int(buffer.frameLength), sampleRate: buffer.format.sampleRate,
                                          channelCount: Int(buffer.format.channelCount), at: ProcessInfo.processInfo.systemUptime)
        let callback = becameReady ? onReady : nil
        if becameReady { onReady = nil }
        lock.unlock()
        callback?()
        if let visualLevel { levelCallback?(visualLevel) }
    }
    private static func rootMeanSquare(_ buffer: AVAudioPCMBuffer) -> Double {
        guard buffer.format.commonFormat == .pcmFormatFloat32, let channels = buffer.floatChannelData else { return 0 }
        let channelCount = Int(buffer.format.channelCount)
        let interleaved = buffer.format.isInterleaved
        var power: Double = 0
        for channel in 0..<channelCount {
            let samples = interleaved ? channels[0].advanced(by: channel) : channels[channel]
            var rms: Float = 0
            vDSP_rmsqv(samples, vDSP_Stride(interleaved ? channelCount : 1), &rms, vDSP_Length(buffer.frameLength))
            power += Double(rms) * Double(rms)
        }
        return sqrt(power / Double(channelCount))
    }
    func finish() {
        lock.lock(); defer { lock.unlock() }
        request?.endAudio()
        request = nil
        onReady = nil
        onLevel = nil
        levelMeter.reset()
    }
    func clear() {
        lock.lock(); defer { lock.unlock() }
        request = nil
        onReady = nil
        onLevel = nil
        levelMeter.reset()
        readiness.reset()
    }
}

/// One delegate per task keeps late callbacks associated with the correct turn.
private final class VoiceRecognitionTaskDelegate: NSObject, SFSpeechRecognitionTaskDelegate {
    private weak var service: VoiceRecognitionService?
    private let turnID: UUID

    init(service: VoiceRecognitionService, turnID: UUID) {
        self.service = service
        self.turnID = turnID
    }
    func speechRecognitionDidDetectSpeech(_ task: SFSpeechRecognitionTask) {
        Task { @MainActor [weak service, turnID] in service?.detectedSpeech(turnID: turnID) }
    }
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription) {
        let text = transcription.formattedString
        Task { @MainActor [weak service, turnID] in service?.receivedPartial(text, turnID: turnID) }
    }
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition recognitionResult: SFSpeechRecognitionResult) {
        let text = recognitionResult.bestTranscription.formattedString
        Task { @MainActor [weak service, turnID] in service?.receivedFinal(text, turnID: turnID) }
    }
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
        let error = task.error as NSError?
        let code = error?.code, domain = error?.domain
        Task { @MainActor [weak service, turnID] in
            service?.taskFinished(successfully: successfully, errorCode: code, errorDomain: domain, turnID: turnID)
        }
    }
}

/// Streams synthesized PCM through the input engine's output graph for echo cancellation.
/// Completion waits for the final buffer to be heard; stale callbacks cannot finish a new line.
@MainActor private final class VoiceNarrationPlayer {
    private let synthesizer=AVSpeechSynthesizer()
    private let player=AVAudioPlayerNode()
    private weak var engine: AVAudioEngine?
    private var identifier: UUID?
    private var completion: ((Bool)->Void)?
    private var pending=0
    private var ended=false
    private var hasAudio=false
    var onEngineUnavailable: (() -> Void)?
    private let converter = VoiceNarrationPCMConverter()

    func attach(to engine: AVAudioEngine) {
        self.engine=engine
        engine.attach(player)
        engine.connect(player,to:engine.mainMixerNode,format:converter.outputFormat)
    }
    func speak(_ utterance: AVSpeechUtterance, completion: @escaping (Bool)->Void) {
        stop()
        let id=UUID();identifier=id;self.completion=completion
        synthesizer.write(utterance) { [weak self] buffer in
            guard let pcm=buffer as? AVAudioPCMBuffer else { return }
            let copy=Self.copy(pcm)
            DispatchQueue.main.async { self?.receive(copy,id:id) }
        }
    }
    func stop(notify: Bool = true) {
        identifier=nil
        let callback=completion;completion=nil
        synthesizer.stopSpeaking(at:.immediate)
        player.stop();pending=0;ended=false;hasAudio=false
        converter.reset()
        if notify {callback?(false)}
    }
    func detach() {
        stop(notify:false)
        if let engine {engine.disconnectNodeOutput(player);engine.detach(player)}
        engine=nil
    }
    private func receive(_ buffer: AVAudioPCMBuffer?,id: UUID) {
        guard identifier == id else {return}
        guard engine?.isRunning == true else {
            onEngineUnavailable?()
            return
        }
        guard let buffer else {stop();return}
        do {
            let buffers = try converter.convert(buffer)
            for converted in buffers {schedule(converted,id:id)}
            if buffer.frameLength == 0 {ended=true;completeIfReady(id)}
        } catch {stop()}
    }
    private func schedule(_ buffer: AVAudioPCMBuffer,id: UUID) {
        hasAudio=true
        pending+=1
        player.scheduleBuffer(buffer,completionCallbackType:.dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.identifier == id else {return}
                self.pending-=1;self.completeIfReady(id)
            }
        }
        if !player.isPlaying {player.play()}
    }
    private func completeIfReady(_ id: UUID) {
        guard identifier == id, ended, pending == 0 else {return}
        let success=hasAudio
        identifier=nil;player.stop()
        let callback=completion;completion=nil;callback?(success)
    }
    nonisolated private static func copy(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let result=AVAudioPCMBuffer(pcmFormat:source.format,frameCapacity:max(1,source.frameLength)) else {return nil}
        result.frameLength=source.frameLength
        // AVSpeechSynthesizer uses an empty PCM buffer as its end marker, not audio storage.
        guard source.frameLength > 0 else { return result }
        let input=UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating:source.audioBufferList))
        let output=UnsafeMutableAudioBufferListPointer(result.mutableAudioBufferList)
        for index in input.indices {
            guard let from=input[index].mData, let to=output[index].mData else {continue}
            memcpy(to,from,Int(input[index].mDataByteSize))
        }
        return result
    }
}


/// Fixed graph format, independent of the selected speech voice or hardware sample rate.
/// One streaming converter per utterance preserves its resampling state across TTS chunks.
final class VoiceNarrationPCMConverter {
    let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    func reset() { converter = nil; inputFormat = nil }

    func convert(_ source: AVAudioPCMBuffer) throws -> [AVAudioPCMBuffer] {
        let finishing = source.frameLength == 0
        if !finishing && converter == nil {
            inputFormat = source.format
            converter = AVAudioConverter(from: source.format, to: outputFormat)
        }
        guard let converter else {
            if finishing { return [] }
            throw ConversionError.unsupportedFormat
        }
        guard finishing || inputFormat == source.format else { throw ConversionError.changedFormat }
        var offset: AVAudioFrameCount = 0
        var result: [AVAudioPCMBuffer] = []
        var inputFailed = false
        while true {
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4096) else {
                throw ConversionError.allocation
            }
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { requested, status in
                guard !finishing else { status.pointee = .endOfStream; return nil }
                guard offset < source.frameLength else { status.pointee = .noDataNow; return nil }
                let count = min(requested, source.frameLength - offset)
                guard count > 0, let chunk = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: count) else {
                    inputFailed = true; status.pointee = .noDataNow; return nil
                }
                chunk.frameLength = count
                let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
                let output = UnsafeMutableAudioBufferListPointer(chunk.mutableAudioBufferList)
                let stride = Int(source.format.streamDescription.pointee.mBytesPerFrame)
                for index in input.indices {
                    if let from = input[index].mData, let to = output[index].mData {
                        memcpy(to, from.advanced(by: Int(offset) * stride), Int(count) * stride)
                    }
                }
                offset += count
                status.pointee = .haveData
                return chunk
            }
            if let error { throw error }
            if inputFailed { throw ConversionError.allocation }
            if status == .error { throw ConversionError.unsupportedFormat }
            if output.frameLength > 0 { result.append(output) }
            if status == .inputRanDry || status == .endOfStream { return result }
            // A malformed converter must not spin on the main actor.
            if output.frameLength == 0 { throw ConversionError.noProgress }
        }
    }
    private enum ConversionError: Error { case unsupportedFormat, changedFormat, allocation, noProgress }
}
