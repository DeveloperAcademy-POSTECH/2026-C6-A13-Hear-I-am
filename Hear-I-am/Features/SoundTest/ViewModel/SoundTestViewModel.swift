import SwiftUI
import HearIAmCore

/// Temporary tab for hearing the guidance signals on a real device. Delete the SoundTest folder and its
/// HearRootView line when testing is done. Every tap and sound is logged.
/// Since 10/21 it holds only what guidance plays; the tone, buzz and direction-finding trials are gone.
@MainActor final class SoundTestViewModel: ObservableObject {
    @Published var warning: WarningLevel?
    @Published var lastEvent="아직 없음"
    @Published var logStatus=""
    /// The warning tone guidance plays, chosen earlier in this tab and saved.
    let warningTone=SignalPlayer.savedWarningTone
    let signals=SignalPlayer()
    let voice=GuidanceSpeech()
    let log=SoundTestLog()

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
        setWarning(nil);signals.shutdown();voice.deactivate()
        record("tab_close","");log.close()
    }
    func record(_ event: String, _ detail: String) {
        lastEvent=detail.isEmpty ? event : "\(event) · \(detail)"
        log.record(event,detail)
    }

    // ① sounds
    func setWarning(_ level: WarningLevel?) { warning=level;signals.setWarning(level) }
    func playArrival() { signals.play(.arrival) }
    func tick(toRight: Bool) { signals.play(.directionTick(toRight:toRight)) }
    func playAligned() { signals.play(.aligned) }

    // ② speech
    func speak(_ text: String) { record("test_speech",text);voice.play([text]) }
    /// The side of the next point, said louder than other lines as in guidance.
    func speakNextSide(_ text: String) {
        record("test_speech",text+" next_side")
        voice.stop();voice.direction(text,volume:SignalVolume.nextSide)
    }
}
