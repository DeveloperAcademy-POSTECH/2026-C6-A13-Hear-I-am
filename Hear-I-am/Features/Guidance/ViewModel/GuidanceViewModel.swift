import SwiftUI
import Combine
import AVFoundation
import HearIAmCore

/// Portrait guidance over a restored stage. One synthesizer reads every instruction in order;
/// a 0.1 s tick drives phase changes from fresh, verified poses.
/// Phase-specific actions live in the GuidanceViewModel+<Phase> files.
@MainActor final class GuidanceViewModel: ObservableObject {
    @Published var phase: GuidancePhase = .selection {
        didSet { run?.setRunning(phase == .guiding,uptime:ProcessInfo.processInfo.systemUptime) }
    }
    @Published var selected: ScanManifest?
    @Published var instructionDone=false
    @Published var speaking=false
    @Published var spokenText=""
    @Published var audioIssue: String?
    @Published var message=""
    @Published var countdown=8
    @Published var departureReady=false
    @Published var startDistance: Double?
    @Published var cue: GuidanceCue?
    @Published var arrivedName: String?
    @Published var showExit=false
    @Published var savingRecord=false
    @Published var saveError: String?
    let tracking=ARSessionController(purpose:.guidance)
    let voice=GuidanceSpeech()
    /// Earbud tones (warning, arrival) and waist vibration for direction, decided 10/17.
    let signals=SignalPlayer()
    let haptics=DirectionHaptics()
    var landmarks=LandmarkDetector()
    var warnings=WarningGate()
    var corrections=CorrectionGate()
    var steps=StepGate()
    var distances=DistanceGate()
    var arrivalShownAt: Double?
    /// Direction, correction and distance signals wait while the ding rings (10/19); safety signals do not.
    var quietUntil: Double?
    /// One direction signal is owed: after the ding, or after leaving the circle around the target.
    var directionPending=false
    var escape: EscapeState?
    var guide: RouteGuide?
    var run: GuidanceRun?
    var pendingRecord: GuidanceRecord?
    var departureGate=DepartureGate()
    var readyAnnounced=false
    var lastPoseTime: Double?
    /// The pose of the current tick, written next to every signal in the trial log.
    var signalPose: (point: FloorPoint, heading: Double, time: Double)?
    var timer: Timer?
    var countdownTask: Task<Void,Never>?
    var generation=UUID()
    var active=true
    var started=false
    var observations: [NSObjectProtocol]=[]
    private var trackingSubscription: AnyCancellable?
    var currentInstruction: [String]=[]

    let interactionSettings: GuidanceInteractionSettings
    var canAdvanceInstruction: Bool {
        interactionSettings.canAdvanceInstruction(done:instructionDone,speaking:speaking,audioFailed:audioIssue != nil)
    }
    var hasStarted: Bool { started }
    var targetIndex: Int { guide?.targetIndex ?? 1 }
    var targetName: String { GuidanceCopy.target(targetIndex,last:(selected?.route?.points.count ?? 2)-1) }
    var headline: GuidanceHeadline {
        GuidanceHeadline(phase:phase,targetName:targetName,hasStarted:started,departureReady:departureReady,
                         departureStatus:departureStatus,arrivedName:arrivedName,cue:cue,message:message)
    }

    init(defaults: UserDefaults = .standard) {
        interactionSettings=GuidanceInteractionSettings(defaults:defaults)
        tracking.showMesh=false
        trackingSubscription=tracking.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        voice.onSpeaking={ [weak self] in self?.speaking=$0;self?.signals.setSpeechActive($0) }
        signals.onEvent={ [weak self] in self?.logSignal($0,$1) }
        haptics.onEvent={ [weak self] in self?.logSignal($0,$1) }
        voice.onText={ [weak self] in self?.spokenText=$0;self?.logSignal("voice",$0) }
        voice.onError={ [weak self] text in
            guard let self else { return }
            self.audioIssue=text;self.instructionDone=false
            if self.phase == .guiding || self.phase == .starting {
                self.guide?.pause();self.phase = self.started ? .paused : .departure;self.message="음성 재생을 확인한 후 다시 시작해주세요."
            }
        }
        observeAudioSession()
        timer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    deinit {
        timer?.invalidate();countdownTask?.cancel()
        observations.forEach {NotificationCenter.default.removeObserver($0)}
    }

    /// Re-reads the instruction for the current phase.
    func replay() {
        guard active else { return }
        if phase == .finishing || phase == .completed { playCompletion();return }
        if phase == .countdown { beginWear();return }
        if phase == .guiding {
            guard let pose=freshPose(), let guide, let cue=guide.cue(position:pose.point,headingDegrees:pose.heading) else { return }
            read(["\(targetName)으로 이동합니다. \(cue.speech)"]);return
        }
        if phase == .interrupted { read(["안내를 멈췄습니다. 휴대폰을 손에 들고 확인점을 다시 확인해주세요."]);return }
        if phase == .paused { read(["안내를 일시정지했습니다. 현재 위치와 저장된 동선을 확인한 뒤 다시 시작해주세요."]);return }
        if phase == .wear { read(["휴대폰을 허리 앞쪽에 세로로 고정해주세요. 후면 카메라는 몸 바깥쪽을 향하고 렌즈는 가리지 말아주세요."]);return }
        if phase == .departure { read([departureStatus]);return }
        read(currentInstruction)
    }
    func read(_ texts: [String], after: (()->Void)? = nil) {
        audioIssue=nil;instructionDone=false;currentInstruction=texts
        let operation=generation
        voice.play(texts) { [weak self] finished in
            guard let self, finished, self.generation == operation, self.active else { return }
            self.instructionDone=true;after?()
        }
    }
    /// Cancels pending speech callbacks and the countdown; late callbacks see a new generation.
    func invalidateTasks() {
        generation=UUID();countdownTask?.cancel();countdownTask=nil;voice.stop();instructionDone=false;arrivedName=nil;arrivalShownAt=nil
        escape=nil;quietUntil=nil;directionPending=false;signals.setWarning(nil);signals.setWarningQuiet(false);haptics.stop()
    }
    /// A pose no older than 0.5 s from a verified session, or nil.
    func freshPose() -> (point: FloorPoint, heading: Double, time: Double)? {
        guard tracking.ready, let p=tracking.position, let heading=tracking.heading, let time=tracking.guidancePoseTime,
              ProcessInfo.processInfo.systemUptime-time >= 0, ProcessInfo.processInfo.systemUptime-time <= 0.5 else { return nil }
        return (FloorPoint(p.x,p.y),heading,time)
    }

    private func tick() {
        guard active, !showExit else { return }
        if phase == .restoring { tickRestoring();return }
        if phase == .checkpoint { tickCheckpoint();return }
        if [.wear,.countdown,.departure,.starting,.guiding,.paused].contains(phase), !tracking.ready {
            interrupt("위치 추적이 끊겼어요. 확인점을 다시 확인해주세요.");return
        }
        if let p=tracking.position, let time=tracking.guidancePoseTime,
           ProcessInfo.processInfo.systemUptime-time >= 0, ProcessInfo.processInfo.systemUptime-time <= 0.5,
           let first=selected?.route?.points.first {
            startDistance=FloorPoint(p.x,p.y).distance(to:first)
        } else { startDistance=nil }
        guard let pose=freshPose() else {
            if phase == .departure { departureReady=false;departureGate.reset();readyAnnounced=false }
            if phase == .guiding || phase == .starting { if tracking.heading == nil { interrupt("몸이 향한 방향을 확인할 수 없어요. 착용 방향을 다시 확인해주세요.") } }
            return
        }
        guard pose.time != lastPoseTime else { return }
        lastPoseTime=pose.time;signalPose=pose
        if let first=selected?.route?.points.first { startDistance=pose.point.distance(to:first) }
        if phase == .departure, let guide { tickDeparture(pose:pose,guide:guide);return }
        if phase == .paused, escape != nil, let guide { tickEscape(pose:pose,guide:guide);return }
        guard phase == .guiding, let guide else { return }
        tickGuiding(pose:pose,guide:guide)
    }
}

extension GuidanceViewModel {
    /// Logs a sound, vibration or spoken line with where the wearer stood and where the target was.
    /// Until 10/19 the log said which signal played but not where, so a run could not be read point by point.
    func logSignal(_ name: String, _ detail: String) {
        guard let pose=signalPose else { tracking.event(name,detail:detail);return }
        var context=String(format:"x=%.2f y=%.2f heading=%.0f",pose.point.x,pose.point.y,pose.heading)
        // The pose is the last fresh one; say so when tracking has not given a new one since.
        let age=ProcessInfo.processInfo.systemUptime-pose.time
        if age > 0.5 { context+=String(format:" pose_age=%.1fs",age) }
        if let guide, guide.route.points.indices.contains(guide.targetIndex) {
            let target=guide.route.points[guide.targetIndex]
            context+=String(format:" target=p%d(%@) dist=%.2f bearing=%+.0f",guide.targetIndex,
                GuidanceCopy.target(guide.targetIndex,last:guide.route.points.count-1),pose.point.distance(to:target),
                StageHeading.bearing(from:pose.point,to:target,headingDegrees:pose.heading))
        }
        tracking.event(name,detail:"\(detail) @ \(context) phase=\(phase)")
    }
}
