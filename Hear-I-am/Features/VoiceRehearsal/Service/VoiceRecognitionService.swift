import AVFoundation
import Combine
import Speech
import UIKit

/// An on-device, Korean command listener for the voice rehearsal experiment.
/// The caller owns when listening is allowed; stop() releases microphone capture completely.
@MainActor final class VoiceRecognitionService: NSObject, ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isAvailable = false
    @Published private(set) var transcript = ""
    @Published private(set) var statusMessage = "음성 입력이 꺼져 있어요"

    var onSpeechDetected: (() -> Void)?
    var onTranscript: ((String) -> Void)?
    /// Only a final recognizer result reaches this callback, once per recognition turn.
    var onFinal: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private var engine: AVAudioEngine?
    private var hasInputTap = false
    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var taskDelegate: VoiceRecognitionTaskDelegate?
    private let inputBridge = VoiceRecognitionInputBridge()
    private var inputLease: UUID?
    private var sessionID: UUID?
    private var turnID: UUID?
    private var wantsListening = false
    private var outputSuppressed = false
    private var speechDetected = false
    private var finalizing = false
    private var contextualStrings: [String] = []
    private var consecutiveFailures = 0
    private var observers: [NSObjectProtocol] = []
    private var restartTimer: Task<Void, Never>?
    private var taskLimitTimer: Task<Void, Never>?
    private var speechLimitTimer: Task<Void, Never>?
    private var endpointTimer: Task<Void, Never>?
    private var finalResultTimer: Task<Void, Never>?

    override init() {
        super.init()
        let center = NotificationCenter.default
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
        // A screen may already be narrating when it asks to prepare listening. Preserve that hold
        // across setup; only an explicit external stop() clears it.
        let initialSuppression = outputSuppressed
        stop()
        outputSuppressed = initialSuppression
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
            let engine = AVAudioEngine()
            self.engine = engine
            // Set before starting either I/O node. Failure disables automatic listening rather than
            // running a speaker listener without the echo processing this experiment depends on.
            try engine.inputNode.setVoiceProcessingEnabled(true)
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw VoiceRecognitionFailure.noInput
            }
            let bridge = inputBridge
            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                bridge.append(buffer)
            }
            hasInputTap = true
            engine.prepare()
            try engine.start()
            guard sessionID == identifier else { stop(); return }
            wantsListening = true
            isAvailable = true
            consecutiveFailures = 0
            if outputSuppressed {
                statusMessage = "안내를 말하는 동안 잠시 기다려주세요"
            } else {
                beginTurn()
            }
        } catch {
            failPermanently("마이크를 준비할 수 없어요. 이어폰 연결을 확인하고 다시 듣기를 눌러주세요.")
        }
    }

    /// Cancels all delayed rearming as well as the current recognition task and microphone tap.
    func stop() {
        stopCapture(restorePlayback: true)
        transcript = ""
        statusMessage = "음성 입력이 꺼져 있어요"
    }

    /// Explicit half-duplex protection for app narration. Capture remains configured, but no buffers
    /// reach ASR while suppressed. The current turn is discarded, never executed after narration.
    /// Do not suppress the short listening chime: the user's first syllable is already being captured.
    func setOutputSuppressed(_ suppressed: Bool) {
        guard outputSuppressed != suppressed else { return }
        outputSuppressed = suppressed
        guard wantsListening else { return }
        restartTimer?.cancel()
        if suppressed {
            retireTurn()
            isListening = false
            statusMessage = "안내를 말하는 동안 잠시 기다려주세요"
        } else {
            scheduleNextTurn(after: 0.35)
        }
    }

    private func beginTurn() {
        guard wantsListening, !outputSuppressed, let recognizer, recognizer.isAvailable, engine?.isRunning == true else {
            if wantsListening, !outputSuppressed {
                failPermanently("음성 입력 연결이 끊겼어요. 다시 듣기를 눌러주세요.")
            }
            return
        }
        retireTurn()
        let identifier = UUID()
        turnID = identifier
        speechDetected = false
        finalizing = false
        transcript = ""
        statusMessage = "말씀하시면 들을게요"
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.contextualStrings = contextualStrings
        request.addsPunctuation = false
        let delegate = VoiceRecognitionTaskDelegate(service: self, turnID: identifier)
        taskDelegate = delegate
        inputBridge.replace(with: request)
        recognitionTask = recognizer.recognitionTask(with: request, delegate: delegate)
        isListening = true
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
        guard self.turnID == turnID, wantsListening, !outputSuppressed, !speechDetected, !finalizing else { return }
        speechDetected = true
        statusMessage = "듣고 있어요"
        speechLimitTimer = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 12_000_000_000) } catch { return }
            self?.finishInput(turnID: turnID)
        }
        onSpeechDetected?()
    }

    fileprivate func receivedPartial(_ text: String, turnID: UUID) {
        guard self.turnID == turnID, wantsListening, !outputSuppressed, !finalizing else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Some recognizer routes provide text before the optional detection delegate callback.
        detectedSpeech(turnID: turnID)
        guard self.turnID == turnID, !outputSuppressed else { return }
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
        guard self.turnID == turnID, wantsListening, !outputSuppressed, !finalizing else { return }
        finalizing = true
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
        guard self.turnID == turnID, wantsListening, !outputSuppressed else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        retireTurn()
        consecutiveFailures = 0
        transcript = text
        isListening = false
        if text.isEmpty {
            statusMessage = "말씀을 알아듣지 못했어요. 다시 말씀해주세요"
            onError?(statusMessage)
            scheduleNextTurn(after: 0.5)
            return
        }
        statusMessage = "말씀을 확인했어요"
        // turnID is invalidated before calling application code so duplicate final callbacks and
        // a cancellation delivered afterward can never execute the command a second time.
        onFinal?(text)
        if wantsListening, !outputSuppressed { scheduleNextTurn(after: 0.5) }
    }

    fileprivate func taskFinished(successfully: Bool, errorDescription: String?, turnID: UUID) {
        guard self.turnID == turnID else { return }
        if successfully {
            // Delegate callbacks cross onto MainActor separately. Give an already-dispatched final
            // result a chance to arrive instead of invalidating it from this completion callback.
            // The finish event itself carries no final transcript; never promote a partial result.
            finalResultTimer?.cancel()
            finalResultTimer = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
                guard let self, self.turnID == turnID else { return }
                self.recognitionFailed("말씀을 끝까지 확인하지 못했어요. 다시 말씀해주세요.", turnID: turnID)
            }
        } else {
            recognitionFailed("음성을 확인하지 못했어요. 잠시 후 다시 들을게요.", turnID: turnID)
        }
    }

    private func recognitionFailed(_ message: String, turnID: UUID) {
        guard self.turnID == turnID, wantsListening else { return }
        retireTurn()
        consecutiveFailures += 1
        if consecutiveFailures >= 3 {
            failPermanently("음성 입력이 반복해서 끊겼어요. 버튼으로 진행하거나 다시 듣기를 눌러주세요.")
            return
        }
        isListening = false
        statusMessage = message
        onError?(message)
        scheduleNextTurn(after: Double(consecutiveFailures))
    }

    private func scheduleNextTurn(after delay: Double) {
        restartTimer?.cancel()
        guard wantsListening, !outputSuppressed, let sessionID else { return }
        restartTimer = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            guard let self, self.sessionID == sessionID, self.wantsListening, !self.outputSuppressed else { return }
            self.beginTurn()
        }
    }

    private func retireTurn() {
        turnID = nil
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
        restartTimer?.cancel(); restartTimer = nil
        retireTurn()
        if let engine {
            engine.stop()
            if hasInputTap { engine.inputNode.removeTap(onBus: 0) }
            engine.reset()
        }
        engine = nil
        hasInputTap = false
        recognizer = nil
        if let inputLease {
            HearAudioSession.releaseVoiceInput(inputLease, restorePlayback: restorePlayback)
        }
        inputLease = nil
        isListening = false
        isAvailable = false
        outputSuppressed = false
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

private enum VoiceRecognitionFailure: Error { case noInput }

/// AVAudioEngine's tap runs off the main actor. Append directly while the tap's buffer is valid;
/// this small lock also keeps endAudio/cancel from racing an in-flight append.
private final class VoiceRecognitionInputBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func replace(with request: SFSpeechAudioBufferRecognitionRequest) {
        lock.lock(); defer { lock.unlock() }
        self.request = request
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        request?.append(buffer)
    }
    func finish() {
        lock.lock(); defer { lock.unlock() }
        request?.endAudio()
        request = nil
    }
    func clear() {
        lock.lock(); defer { lock.unlock() }
        request = nil
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
        let description = task.error?.localizedDescription
        Task { @MainActor [weak service, turnID] in
            service?.taskFinished(successfully: successfully, errorDescription: description, turnID: turnID)
        }
    }
}
