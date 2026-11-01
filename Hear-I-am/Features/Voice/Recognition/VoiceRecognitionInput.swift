import AVFoundation
import Accelerate
import Speech
import HearIAmCore

/// AVAudioEngine's tap runs off the main actor. Append directly while the tap's buffer is valid;
/// this small lock also keeps endAudio/cancel from racing an in-flight append.
final class VoiceRecognitionInputBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var request: VoiceAudioSink?
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
    func replace(with request: VoiceAudioSink,
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
final class VoiceRecognitionTaskDelegate: NSObject, SFSpeechRecognitionTaskDelegate {
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
        let alternatives = recognitionResult.transcriptions.dropFirst().map(\.formattedString)
        Task { @MainActor [weak service, turnID] in service?.receivedFinal(text, alternatives: alternatives, turnID: turnID) }
    }
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
        let error = task.error as NSError?
        let code = error?.code, domain = error?.domain
        Task { @MainActor [weak service, turnID] in
            service?.taskFinished(successfully: successfully, errorCode: code, errorDomain: domain, turnID: turnID)
        }
    }
}
