import SwiftUI
import AVFoundation
import UIKit
import HearIAmCore

/// Temporary tab for checking signals on a real device. Delete the SoundTest folder and its
/// HearRootView line when testing is done. Every tap, sound, vibration and result is logged.
/// Section ④ lives in SoundTestViewModel+Direction.
@MainActor final class SoundTestViewModel: ObservableObject {
    @Published var warning: WarningLevel?
    @Published var warningTone=SignalPlayer.savedWarningTone
    @Published var directionMode=SignalPlayer.directionMode
    @Published var speaking=false
    @Published var lastEvent="아직 없음"
    @Published var logStatus=""
    @Published var probing=false
    @Published var trackingText="꺼짐"
    @Published var jitterText="—"
    @Published var bodyAngle: Double?
    @Published var headAngle: Double?
    @Published var headStatus="확인 전"
    @Published var trial: DirectionTrial?
    @Published var results: [DirectionTrialResult]=[]
    @Published var manualBearing=90.0
    @Published var pitchHertz: Double?
    @Published var pitchStatus="시작 전"
    @Published var pitchVolume=0.12
    @Published var pitchResolution=ContinuousDirectionGate.Resolution.smooth
    let continuous=ContinuousTonePlayer()
    var pitchGate=ContinuousDirectionGate()
    var pitchTimer: Timer?
    var lastPitchLog: Double?
    var pitchObservers: [NSObjectProtocol]=[]
    let signals=SignalPlayer()
    let haptics=DirectionHaptics()
    let voice=GuidanceSpeech()
    let body=BodyHeadingFeed()
    let head=HeadHeadingFeed()
    let probe=TrackingProbe()
    let log=SoundTestLog()
    var detector=LandmarkDetector()
    var sweepGate=DirectionSweepGate()

    init() {
        continuous.onUnavailable={ [weak self] text in
            guard let self else { return }
            self.finishTrial(found:false);self.pitchStatus=text;self.record("continuous_error",text)
        }
        for name in [AVAudioSession.interruptionNotification,AVAudioSession.routeChangeNotification,
                     UIApplication.willResignActiveNotification] {
            pitchObservers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] note in
                if note.name == AVAudioSession.routeChangeNotification,
                   let raw=note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                   AVAudioSession.RouteChangeReason(rawValue:raw) == .categoryChange { return }
                let interrupted=note.name == AVAudioSession.interruptionNotification
                Task { @MainActor in
                    guard let self, self.trial?.mode.isContinuous == true else { return }
                    self.finishTrial(found:false)
                    if interrupted { HearAudioSession.interrupted() }
                    self.pitchStatus="출력 변경 또는 중단";self.record("continuous_stopped",self.pitchStatus)
                }
            })
        }
        signals.onError={ [weak self] text in
            guard let self else { return }
            if self.trial?.mode.isContinuous == true { self.finishTrial(found:false);self.pitchStatus=text }
            self.record("signal_error",text)
        }
        signals.onEvent={ [weak self] in self?.record($0,$1) }
        haptics.onEvent={ [weak self] in self?.record($0,$1) }
        voice.onSpeaking={ [weak self] value in
            guard let self else { return }
            self.speaking=value;self.signals.setSpeechActive(value)
            if value, self.trial?.mode.isContinuous == true {
                self.signals.stopDirection();self.continuous.setHertz(nil);self.pitchGate.suspend()
            }
        }
        voice.onError={ [weak self] in self?.record("speech_error",$0) }
        head.onStatus={ [weak self] in self?.headStatus=$0;self?.record("head_status",$0) }
        probe.onUpdate={ [weak self] state,jitter in
            self?.trackingText=state;self?.jitterText=jitter.map { String(format:"%.1f cm",$0) } ?? "모으는 중"
        }
    }

    deinit { pitchObservers.forEach(NotificationCenter.default.removeObserver) }

    func appear() {
        logStatus=log.open().map { $0 } ?? "기록 파일: SoundTests/"+(log.fileName ?? "")
        record("tab_open","route="+HearAudioSession.route)
        if let error=body.start({ [weak self] in self?.bodySample($0) }) { record("body_error",error) }
        head.start { [weak self] in self?.headSample($0) }
    }
    func disappear() {
        if trial != nil { finishTrial(found:false) }
        continuous.stop();setWarning(nil);signals.shutdown();haptics.shutdown();voice.deactivate()
        body.stop();head.stop();probe.stop();probing=false
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
    func previewSweep(_ degrees: Int) {
        guard trial == nil else { return }
        signals.play(.directionSweep(DirectionSweep(turn:degrees < 0 ? .left : .right,errorDegrees:Double(degrees))))
    }
    func previewAlignment() { guard trial == nil else { return };signals.play(.directionAligned) }
    func beep(_ degrees: Int) { signals.play(.direction(signedDegrees:degrees)) }
    func speak(_ text: String) { record("test_speech",text);voice.play([text]) }
    /// Warning and a correction line together, to hear whether the words are masked.
    func playOverlap() { record("test_overlap","warning_near + "+SignalCopy.turnLeft);setWarning(.near);speak(SignalCopy.turnLeft) }

    // ② haptics
    /// Plays the landmark the way guidance will: vibration, beep, or both, as chosen below.
    func vibrate(_ degrees: Int) { haptics.playDirection(signedDegrees:degrees,signals:signals,mode:directionMode) }
    func setDirectionMode(_ mode: DirectionSignalMode) {
        directionMode=mode;SignalPlayer.directionMode=mode;record("signal_direction_mode",mode.rawValue)
    }
    func toggleProbe() {
        if probing { probe.stop();probing=false;trackingText="꺼짐";jitterText="—";record("probe","off") }
        else { probe.start();probing=true;record("probe","on") }
    }

    // ③ buzz
    func playBuzz(_ hertz: Double, harmonic: Bool) { signals.play(.buzz(hertz:hertz,harmonic:harmonic)) }
}
