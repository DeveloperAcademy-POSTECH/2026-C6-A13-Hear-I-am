import AVFoundation
import HearIAmCore

/// One synthesizer owns the entire portrait flow. Instructions are sequential; directions never backlog.
@MainActor final class GuidanceSpeech: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer=AVSpeechSynthesizer()
    private var queue=NarrationQueue()
    private var utterance: AVSpeechUtterance?
    private var lineID: UUID?
    private var completion: ((Bool)->Void)?
    var onSpeaking: ((Bool)->Void)?
    var onText: ((String)->Void)?
    var onError: ((String)->Void)?
    var isSpeaking: Bool { queue.current != nil }

    override init() { super.init(); synthesizer.delegate=self }

    @discardableResult func play(_ texts: [String], final: Bool = false, completion: ((Bool)->Void)? = nil) -> Bool {
        guard !queue.protectsCompletion else { return false }
        stop()
        guard prepareAudio(), let line=queue.replace(texts,completion:final) else { completion?(false); return false }
        self.completion=completion
        speak(line)
        return true
    }
    func direction(_ text: String, volume: Float = SignalVolume.speech) {
        guard !isSpeaking, prepareAudio(), let line=queue.offerDirection(text) else { return }
        speak(line,volume:volume)
    }
    func stop() {
        let callback=completion;completion=nil
        utterance=nil;lineID=nil;queue.cancel()
        synthesizer.stopSpeaking(at:.immediate)
        onSpeaking?(false);callback?(false)
    }
    func deactivate() { stop();HearAudioSession.deactivate() }
    func audioWasInterrupted() { stop();HearAudioSession.interrupted() }

    private func prepareAudio() -> Bool {
        do {
            try HearAudioSession.activate()
            guard AVAudioSession.sharedInstance().outputVolume > 0 else {
                onError?("소리가 꺼져 있어요. 휴대폰의 음량을 올리고 설명 다시 듣기를 눌러주세요.")
                return false
            }
            return true
        } catch { onError?("음성을 재생할 수 없어요. 설명 다시 듣기로 다시 시도해주세요.");return false }
    }
    private func speak(_ line: NarrationQueue.Line, volume: Float = SignalVolume.speech) {
        let next=AVSpeechUtterance(string:line.text)
        next.voice=AVSpeechSynthesisVoice(language:"ko-KR");next.rate=0.48;next.volume=volume
        utterance=next;lineID=line.id
        onSpeaking?(true);onText?(line.text);synthesizer.speak(next)
    }
    private func finished(_ item: AVSpeechUtterance) {
        guard utterance === item, let lineID, queue.finish(lineID) else { return }
        utterance=nil;self.lineID=nil
        if let next=queue.current { speak(next) }
        else {
            let callback=completion;completion=nil
            onSpeaking?(false);callback?(true)
        }
    }
    private func canceled(_ item: AVSpeechUtterance) {
        guard utterance === item else { return }
        stop();onError?("음성 안내가 중단됐어요. 설명 다시 듣기로 다시 확인해주세요.")
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finished(utterance) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.canceled(utterance) }
    }
}
