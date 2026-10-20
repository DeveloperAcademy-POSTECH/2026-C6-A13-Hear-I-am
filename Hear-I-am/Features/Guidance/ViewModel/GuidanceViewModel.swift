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
    /// Mono counted beeps for body direction; warnings and arrival retain their own sounds.
    let signals=SignalPlayer()
    var directionBeep=CountedDirectionGate()
    var routeNarration=RouteNarrationGate()
    var routeSpeech: (id: UUID, cue: RouteNarrationCue)?
    /// Leave room for the complete alignment bell before starting speech.
    var narrationReadyAt: Double?
    var warnings=WarningGate()
    var steps=StepGate()
    var arrivalShownAt: Double?
    /// The warning pauses briefly on arrival so the ding is not masked.
    var warningHoldUntil: Double?
    var escape: EscapeState?
    var guide: RouteGuide?
    var run: GuidanceRun?
    var pendingRecord: GuidanceRecord?
    var departureGate=DepartureGate()
    var readyAnnounced=false
    var lastPoseTime: Double?
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
        voice.onSpeaking={ [weak self] value in
            guard let self else { return }
            self.speaking=value;self.signals.setSpeechActive(value)
            if value { self.suspendDirection() }
        }
        signals.onEvent={ [weak self] in self?.tracking.event($0,detail:$1) }
        voice.onText={ [weak self] in self?.spokenText=$0 }
        voice.onError={ [weak self] in self?.handleAudioIssue($0) }
        signals.onError={ [weak self] in self?.handleAudioIssue($0) }
        observeAudioSession()
        timer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    deinit {
        timer?.invalidate();countdownTask?.cancel()
        observations.forEach {NotificationCenter.default.removeObserver($0)}
    }

    private func handleAudioIssue(_ text: String) {
        audioIssue=text;instructionDone=false
        cancelRouteSpeech();routeNarration.suspendMotion();narrationReadyAt=nil
        directionBeep.reset();signals.stop();escape=nil
        if phase == .guiding || phase == .starting || phase == .paused {
            guide?.pause();phase = started ? .paused : .departure
            message="소리 출력을 확인한 후 다시 시작해주세요."
        }
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
        routeSpeech=nil
        audioIssue=nil;instructionDone=false;currentInstruction=texts
        let operation=generation
        voice.play(texts) { [weak self] finished in
            guard let self, finished, self.generation == operation, self.active else { return }
            self.instructionDone=true;after?()
        }
    }
    /// Cancels pending speech callbacks and the countdown; late callbacks see a new generation.
    func invalidateTasks() {
        routeSpeech=nil;routeNarration.suspendMotion();narrationReadyAt=nil
        generation=UUID();countdownTask?.cancel();countdownTask=nil;voice.stop();instructionDone=false;arrivedName=nil;arrivalShownAt=nil
        escape=nil;warningHoldUntil=nil;directionBeep.reset();signals.stop();signals.setWarningQuiet(false)
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
            if phase == .guiding || phase == .starting || (phase == .paused && escape != nil) {
                interrupt(tracking.heading == nil ? "몸이 향한 방향을 확인할 수 없어요. 착용 방향을 다시 확인해주세요." : "현재 위치를 확인할 수 없어요. 확인점을 다시 확인해주세요.")
            }
            return
        }
        guard pose.time != lastPoseTime else { return }
        lastPoseTime=pose.time
        if let first=selected?.route?.points.first { startDistance=pose.point.distance(to:first) }
        if phase == .departure, let guide { tickDeparture(pose:pose,guide:guide);return }
        if phase == .paused, escape != nil, let guide { tickEscape(pose:pose,guide:guide);return }
        guard phase == .guiding, let guide else { return }
        tickGuiding(pose:pose,guide:guide)
    }
}
