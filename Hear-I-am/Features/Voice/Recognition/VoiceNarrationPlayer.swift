import AVFoundation

/// Streams synthesized PCM through the input engine's output graph for echo cancellation.
/// Completion waits for the final buffer to be heard; stale callbacks cannot finish a new line.
@MainActor final class VoiceNarrationPlayer {
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
