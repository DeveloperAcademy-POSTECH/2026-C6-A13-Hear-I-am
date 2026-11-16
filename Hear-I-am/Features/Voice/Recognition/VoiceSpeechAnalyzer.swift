import AVFoundation
import Speech
import OSLog
import HearIAmCore

enum VoiceLanguageModelBuilder {
    struct Prepared: @unchecked Sendable {
        let configuration: SFSpeechLanguageModel.Configuration
        let lease: VoiceModelCache.Lease
    }
    static let vocabularyInvalidated = Notification.Name("HearIAm.voiceVocabularyInvalidated")
    private static let cache = VoiceModelCache(
        root: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceLanguageModel", isDirectory: true),
        onCleanupFailure: { count in
            Logger(subsystem: "org.heariam.poc4.scanlab", category: "VoiceModelCache")
                .error("Custom voice cache cleanup failed for \(count) items; retrying on next library load.")
        }
    )

    /// Called after a committed library change. Pending preparations become obsolete immediately;
    /// live requests retain their files until Speech reports that they have actually completed.
    @MainActor static func invalidateLibraryVocabulary() {
        cache.invalidate()
        NotificationCenter.default.post(name: vocabularyInvalidated, object: nil)
    }
    static func cleanUnusedCache() { cache.scheduleCleanup() }

    private struct ModelUse: @unchecked Sendable {
        let model: Prepared
        let task: SFSpeechRecognitionTask
    }
    static func retain(_ model: Prepared, untilFinished task: SFSpeechRecognitionTask) {
        let use = ModelUse(model: model, task: task)
        Task.detached(priority: .utility) {
            // cancel() is asynchronous. Do not rely on the service/delegate lifetime or a fixed
            // grace period to decide that Speech has stopped reading its language-model files.
            while use.task.state != .completed {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            withExtendedLifetime(use.model) {}
        }
    }

    /// Stable across launches, unlike Hasher: FNV-1a over every phrase and weight.
    static func key(_ phrases: [VoiceVocabulary.Phrase]) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in (VoiceVocabulary.version + phrases.map { "\($0.text)\u{1F}\($0.count)" }.joined(separator: "\u{1E}")).utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
    static func prepare(_ phrases: [VoiceVocabulary.Phrase], locale: Locale) async -> Prepared? {
        do {
            guard !Task.isCancelled else { return nil }
            let lease = try cache.acquire()
            let folder = lease.folder
            let configuration = SFSpeechLanguageModel.Configuration(languageModel: folder.appendingPathComponent("model"),
                                                                    vocabulary: folder.appendingPathComponent("vocabulary"))
            let asset = folder.appendingPathComponent("data.bin")
            let data = SFCustomLanguageModelData(locale: locale, identifier: "org.heariam.voice", version: VoiceVocabulary.version) {}
            for phrase in phrases { data.insert(phraseCount: SFCustomLanguageModelData.PhraseCount(phrase: phrase.text, count: phrase.count)) }
            try await data.export(to: asset)
            guard !Task.isCancelled, lease.isCurrent else { return nil }
            try await SFSpeechLanguageModel.prepareCustomLanguageModel(for: asset, configuration: configuration)
            guard !Task.isCancelled, lease.isCurrent else { return nil }
            return Prepared(configuration: configuration, lease: lease)
        } catch {
            return nil
        }
    }
}

/// One listening turn on the iOS 26 SpeechAnalyzer engine (#92), shaped like an SFSpeech task: partial
/// text while speaking, one final text with alternatives after endAudio(), or an error.
@available(iOS 26.0, *)
final class VoiceAnalyzerTurn: VoiceAudioSink, VoiceAnalyzerCancelling, @unchecked Sendable {
    /// Without `.fastResults` the transcriber held its words until about 11.4 s of audio had passed, on the
    /// phone and on a Mac alike (11/03): a request showed 11.6 s after listening began and could not cut
    /// the app's speech. With it, words come about 0.2 s after they are said; the final text is unchanged.
    private static let reporting: Set<SpeechTranscriber.ReportingOption> = [.volatileResults, .alternativeTranscriptions, .fastResults]
    private let lock = NSLock()
    private let analyzer: SpeechAnalyzer
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let format: AVAudioFormat
    private var converter: AVAudioConverter?
    private var task: Task<Void, Never>?
    private var ended = false

    /// Installs the Korean model if needed and returns the audio format it reads; nil when unavailable.
    static func prepare(locale: Locale) async -> AVAudioFormat? {
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: reporting, attributeOptions: [])
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch { return nil }
        return await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
    }

    init(locale: Locale, format: AVAudioFormat, contextualStrings: [String], service: VoiceRecognitionService, turnID: UUID) {
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: Self.reporting, attributeOptions: [])
        analyzer = SpeechAnalyzer(modules: [transcriber])
        self.format = format
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.continuation = continuation
        let analyzer = analyzer
        task = Task { [weak service] in
            do {
                let context = AnalysisContext()
                context.contextualStrings[.general] = contextualStrings
                try await analyzer.setContext(context)
                try await analyzer.start(inputSequence: stream)
                var finalized = "", alternatives: [String] = []
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        finalized += text
                        alternatives = result.alternatives.map { finalized.dropLast(text.count) + String($0.characters) }
                    }
                    let shown = result.isFinal ? finalized : finalized + text
                    if !shown.trimmingCharacters(in: .whitespaces).isEmpty {
                        await MainActor.run { [weak service] in service?.analyzerPartial(shown, turnID: turnID) }
                    }
                }
                let heard = finalized, others = alternatives
                await MainActor.run { [weak service] in service?.analyzerFinal(heard, alternatives: others, turnID: turnID) }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak service] in service?.analyzerFailed(error, turnID: turnID) }
            }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard !ended, let converted = convert(buffer) else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }
    func endAudio() {
        lock.lock()
        guard !ended else { lock.unlock(); return }
        ended = true
        lock.unlock()
        continuation.finish()
        let analyzer = analyzer
        Task { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
    }
    func cancel() {
        lock.lock(); ended = true; lock.unlock()
        continuation.finish()
        task?.cancel()
        let analyzer = analyzer
        Task { await analyzer.cancelAndFinishNow() }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        if converter == nil || converter?.inputFormat != buffer.format { converter = AVAudioConverter(from: buffer.format, to: format) }
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return buffer
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }
}
