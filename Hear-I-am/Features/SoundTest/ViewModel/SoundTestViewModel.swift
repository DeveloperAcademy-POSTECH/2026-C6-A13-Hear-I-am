import SwiftUI
import HearIAmCore

/// Signal tutorial tab (#74): lets visually impaired users listen to and learn the active guidance signals.
@MainActor final class SoundTestViewModel: ObservableObject {
    @Published var alignedTone=SignalPlayer.savedAlignedTone
    @Published var lastEvent="버튼을 눌러 소리를 들어보세요"
    @Published var logStatus=""
    let signals=SignalPlayer()
    let voice=GuidanceSpeech()
    let log=SoundTestLog()
    private var completionTask: Task<Void, Never>?

    init() {
        signals.onEvent={ [weak self] in self?.record($0,$1) }
        voice.onSpeaking={ [weak self] in self?.signals.setSpeechActive($0) }
        voice.onError={ [weak self] in self?.record("speech_error",$0) }
    }

    func appear() {
        logStatus=log.open().map { $0 } ?? "기록 파일: SoundTests/"+(log.fileName ?? "")
        record("tab_open","route="+HearAudioSession.route)
    }
    func disappear() {
        completionTask?.cancel();completionTask=nil
        signals.shutdown();voice.deactivate()
        record("tab_close","");log.close()
    }
    func record(_ event: String, _ detail: String) {
        lastEvent=detail.isEmpty ? event : "\(event) · \(detail)"
        log.record(event,detail)
    }

    // ① sounds
    func playArrival() { completionTask?.cancel();signals.play(.arrival) }
    func tick(toRight: Bool) { completionTask?.cancel();signals.play(.directionTick(toRight:toRight)) }
    func playAligned() { completionTask?.cancel();signals.playAligned() }
    func selectAligned(_ tone: AlignedTone) {
        completionTask?.cancel()
        alignedTone=tone;signals.setAlignedTone(tone);signals.playAligned()
    }

    // ② speech
    func speak(_ text: String) { completionTask?.cancel();record("tutorial_speech",text);voice.play([text]) }
    /// The side of the next point, said louder than other lines as in guidance.
    func speakNextSide(_ text: String) {
        completionTask?.cancel()
        record("tutorial_speech",text+" next_side")
        voice.stop();voice.direction(text,volume:SignalVolume.nextSide)
    }
    /// Plays the final arrival ding followed 0.7 s later by "마지막 지점 도착", matching actual completion.
    func playCompletionPreview() {
        completionTask?.cancel()
        voice.stop()
        signals.play(.arrival)
        record("tutorial_completion",GuidanceCopy.completed)
        completionTask=Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds:UInt64(GuidanceViewModel.dingBeforeSpeech*1e9))
            guard !Task.isCancelled, let self else { return }
            self.voice.play([GuidanceCopy.completed])
        }
    }
}
