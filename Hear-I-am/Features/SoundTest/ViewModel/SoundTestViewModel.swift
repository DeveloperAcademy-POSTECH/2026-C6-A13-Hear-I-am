import SwiftUI
import HearIAmCore

/// Temporary tab for checking signals on a real device. Delete the SoundTest folder and its
/// HearRootView line when testing is done. Every tap, sound and result is logged.
/// Section ③ lives in SoundTestViewModel+Direction. No vibration since 10/20 (team decision).
@MainActor final class SoundTestViewModel: ObservableObject {
    @Published var warning: WarningLevel?
    @Published var warningTone=SignalPlayer.savedWarningTone
    @Published var deadbandDegrees=SignalPlayer.directionDeadbandDegrees
    @Published var speaking=false
    @Published var lastEvent="아직 없음"
    @Published var logStatus=""
    @Published var bodyAngle: Double?
    @Published var headAngle: Double?
    @Published var headStatus="확인 전"
    @Published var trial: DirectionTrial?
    @Published var results: [DirectionTrialResult]=[]
    let signals=SignalPlayer()
    let voice=GuidanceSpeech()
    let body=BodyHeadingFeed()
    let head=HeadHeadingFeed()
    let log=SoundTestLog()
    var directionTicks=DirectionTickGate(deadbandDegrees:SignalPlayer.directionDeadbandDegrees)

    init() {
        signals.onEvent={ [weak self] in self?.record($0,$1) }
        voice.onSpeaking={ [weak self] value in self?.speaking=value;self?.signals.setSpeechActive(value) }
        voice.onError={ [weak self] in self?.record("speech_error",$0) }
        head.onStatus={ [weak self] in self?.headStatus=$0;self?.record("head_status",$0) }
    }

    func appear() {
        logStatus=log.open().map { $0 } ?? "기록 파일: SoundTests/"+(log.fileName ?? "")
        record("tab_open","route="+HearAudioSession.route)
        if let error=body.start({ [weak self] in self?.bodySample($0) }) { record("body_error",error) }
        head.start { [weak self] in self?.headSample($0) }
    }
    func disappear() {
        if trial != nil { finishTrial(found:false) }
        setWarning(nil);signals.shutdown();voice.deactivate()
        body.stop();head.stop()
        record("tab_close","");log.close()
    }
    func record(_ event: String, _ detail: String) {
        lastEvent=detail.isEmpty ? event : "\(event) · \(detail)"
        log.record(event,detail)
    }

    // ① signals
    func setWarning(_ level: WarningLevel?) { warning=level;signals.setWarning(level) }
    func setWarningTone(_ tone: WarningTone) { warningTone=tone;signals.setWarningTone(tone) }
    func playArrival() { signals.play(.arrival) }
    func beep(_ degrees: Int) { signals.play(.direction(signedDegrees:degrees)) }
    func tick(toRight: Bool) { signals.play(.directionTick(toRight:toRight)) }
    func setDeadband(_ degrees: Double) {
        deadbandDegrees=degrees
        SignalPlayer.directionDeadbandDegrees=degrees
        directionTicks.deadbandDegrees=degrees
        record("direction_deadband",String(format:"±%.0f°",degrees))
    }
    func speak(_ text: String) { record("test_speech",text);voice.play([text]) }
    /// Warning and a correction line together, to hear whether the words are masked.
    func playOverlap() { record("test_overlap","warning_near + "+SignalCopy.left);setWarning(.near);speak(SignalCopy.left) }

    // ② buzz
    func playBuzz(_ hertz: Double, harmonic: Bool) { signals.play(.buzz(hertz:hertz,harmonic:harmonic)) }
}
