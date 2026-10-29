import SwiftUI
import Combine
import AVFoundation
import HearIAmCore

/// Portrait guidance over a restored stage. One synthesizer reads every instruction in order;
/// a 0.1 s tick drives phase changes from fresh, verified poses.
/// Phase-specific actions live in the GuidanceViewModel+<Phase> files.
@MainActor final class GuidanceViewModel: ObservableObject {
    @Published var phase: GuidancePhase = .selection {
        didSet {
            if voiceExperiment, voiceMode == .performance, phase == .starting {voicePerformanceInputClosed=true}
            run?.setRunning(phase == .guiding,uptime:ProcessInfo.processInfo.systemUptime);captureReplay(force:true);syncVoiceListening()
            if oldValue != phase {syncVoiceConversationLanguage()}
        }
    }
    @Published var selected: ScanManifest?
    @Published var instructionDone=false
    @Published var speaking=false
    @Published var spokenText=""
    @Published var audioIssue: String? { didSet {syncVoiceListening()} }
    @Published var message=""
    @Published var departureReady=false
    @Published var startDistance: Double?
    @Published var approachNotice: String?
    @Published var cue: GuidanceCue?
    @Published var arrivedName: String?
    @Published var performanceHoldRemaining: Double = 0
    @Published var showExit=false
    @Published var savingRecord=false
    @Published var saveError: String?
    let voiceExperiment: Bool
    @Published var voiceMode: VoiceUsageMode?
    @Published var voiceChoosingMode=false
    @Published var voiceSelectionControlsVisible=false
    @Published var voicePerformanceInputClosed=false
    @Published var voiceSearchQuery: String?
    @Published var voiceSearchIDs: [UUID]?
    var voiceInitialPromptPending=false
    @Published var voiceListeningEnabled=true
    @Published var voiceTurnActive=false
    /// Whether speaking over the line now playing cuts it (#92, 10/29). Only a list to choose from, the stage
    /// list, may be cut; replies and step lines that follow a request play to the end and the speech over
    /// them is dropped, so the app is not stopped half way through doing what was asked.
    var voiceNarrationInterruptible=false
    /// A command waiting for 「응」 or 「아니」: a guess of the Apple Intelligence model (#87), or leaving a started run.
    var pendingVoiceIntent: VoiceCommand?
    /// The request the user already made to the voice agent on Home (#90).
    var voiceInitialRequest: String?
    /// Opens the 공연 사전 저장 tab when a request in the stage list is about pre-saved plans.
    var onOpenPlans: (() -> Void)?
    /// Opens a new scan from the 장소 tab when the stage list is asked for one, or when nothing is saved.
    var onOpenScan: (() -> Void)?
    /// Stage and mode Siri already named (#91).
    var voiceInitialStageID: UUID?
    var voiceInitialMode: VoiceUsageMode?
    /// The request the Apple Intelligence model is reading; a newer request makes its answer stale (#92).
    var voicePendingRequest: String?
    /// Guidance acts on speech only after 「히얼아이엠」 and while that conversation goes on (#90).
    var voiceConversationDeadline: Double?
    /// Once called, the conversation stays open through the step-by-step phases, so the next screen
    /// does not need another call. A tap closes it; the next call opens it again.
    var voiceConversationOpen=false
    var voiceConversationTimer: Task<Void,Never>?
    @Published var voiceInputError: String?
    let voiceRecognition=VoiceRecognitionService()
    let listeningChime=VoiceListeningChime()
    var voiceSubscriptions=Set<AnyCancellable>()
    var voiceInputTask: Task<Void,Never>?
    var voiceRecognitionRequested=false
    var voiceReadyChimePending=false
    var voicePausedNavigation=false
    var voiceStages: [ScanManifest]=[]
    var voiceStagePaths: [UUID:[String]]=[:]
    let tracking=ARSessionController(purpose:.guidance)
    let voice=GuidanceSpeech()
    /// Earbud tones: warning, arrival ding, direction ticks. No vibration since 10/20 (team decision).
    let signals=SignalPlayer()
    var directionTicks=DirectionTickGate(deadbandDegrees:SignalPlayer.directionDeadbandDegrees)
    /// Set on leaving the start and on reaching a point: the next direction cue speaks the side of the new target once.
    var announceNextSide=false
    /// Set when the next target spot stands on a chair or stairs: speaks 「의자」 or 「계단」 once when aligned before distance marks (#76).
    var announceStepHint=false
    /// A side to say on turning away that waits for the line being spoken (#57).
    var pendingTurnSide=false
    /// Ticks wait while a side word is spoken: speech starts a little late, so a tick would come first (10/21).
    var ticksWaitForWord=false
    var warnings=WarningGate()
    var distances=DistanceGate()
    var arrivalShownAt: Double?
    /// Direction, correction and distance signals wait while the ding rings (10/19); safety signals do not.
    var quietUntil: Double?
    /// When non-nil, the performer has just arrived at a chair or stairs and is aligning with its `facingEdge` before moving to the next point (#76).
    var aligningStep: StageObstacle?
    var escape: EscapeState?
    var guide: RouteGuide?
    var approachGuide: RouteGuide?
    var run: GuidanceRun?
    var pendingRecord: GuidanceRecord?
    var departureGate=DepartureGate()
    var readyAnnounced=false
    var lastPoseTime: Double?
    /// The pose of the current tick, written next to every signal in the trial log.
    var signalPose: (point: FloorPoint, heading: Double, time: Double)?
    var timer: Timer?
    var generation=UUID()
    var active=true
    var started=false
    var observations: [NSObjectProtocol]=[]
    private var trackingSubscription: AnyCancellable?
    var currentInstruction: [String]=[]

    /// Next-step buttons work while an instruction is still being read; pressing one stops it (10/21).
    /// Position and checkpoint checks still apply.
    // Speech (including a previous playback error) never locks a next-step button.
    // Each action stops the old narration and retries audio; its own tracking/position guards still apply.
    var canAdvanceInstruction: Bool { active && !savingRecord && (!voiceExperiment || voiceMode != nil) }
    var hasStarted: Bool { started }
    var targetIndex: Int { phase == .approaching ? 0 : guide?.facingPointIndex ?? guide?.targetIndex ?? 1 }
    var targetName: String { GuidanceCopy.target(targetIndex,last:(selected?.route?.points.count ?? 2)-1) }
    var headline: GuidanceHeadline {
        if phase == .guiding, let index=guide?.facingPointIndex, let route=guide?.route, let facing=route.facing(at:index) {
            return GuidanceHeadline(facing:facing,pointName:route.pointLabel(at:index))
        }
        if phase == .guiding, performanceHoldRemaining > 0 {
            return GuidanceHeadline(holdingSeconds:performanceHoldRemaining,pointName:guide?.route.pointLabel(at:max(1,targetIndex-1)) ?? SignalCopy.point(max(1,targetIndex-1)))
        }
        return GuidanceHeadline(phase:phase,targetName:targetName,hasStarted:started,departureReady:departureReady,
                         departureStatus:departureStatus,arrivedName:arrivedName,cue:cue,message:message)
    }

    init(voiceExperiment: Bool = false) {
        self.voiceExperiment=voiceExperiment
        tracking.showMesh=false
        trackingSubscription=tracking.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        voice.onSpeaking={ [weak self] value in
            self?.speaking=value;self?.signals.setSpeechActive(value)

        }
        signals.onEvent={ [weak self] in self?.logSignal($0,$1) }
        voice.onText={ [weak self] in self?.spokenText=$0;self?.logSignal("voice",$0) }
        voice.onError={ [weak self] text in
            guard let self else { return }
            self.audioIssue=text;self.instructionDone=false
            if self.phase == .guiding || self.phase == .starting || self.phase == .approaching {
                self.approachGuide=nil;self.signals.stopDirection();self.guide?.pause();self.phase = self.started ? .paused : .departure;self.message="음성 재생을 확인한 후 다시 시작해주세요."
            }
        }
        if voiceExperiment {
            voice.bufferedOutput={ [weak self] utterance, completion in
                self?.voiceRecognition.speakNarration(utterance,completion:completion) ?? false
            }
            voice.stopBufferedOutput={ [weak self] in self?.voiceRecognition.stopNarration() }
        }
        configureVoiceExperiment()
        observeAudioSession()
        timer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    deinit {
        timer?.invalidate()
        observations.forEach {NotificationCenter.default.removeObserver($0)}
    }

    /// Re-reads the instruction for the current phase.
    func replay() {
        guard active else { return }
        if voiceExperiment, phase == .selection {
            // Replay the current question, not the last microphone error announcement.
            if voiceChoosingMode {readVoiceModeQuestion()}
            else if voiceSearchQuery != nil {announceVoiceStageResults()}
            else {selectionDescription(empty:voiceStages.isEmpty)}
            return
        }
        if phase == .finishing || phase == .completed { playCompletion();return }
        if phase == .approaching {
            if let pose=freshPose(), let cue=approachGuide?.cue(position:pose.point,headingDegrees:pose.heading) { read(["출발점으로 이동합니다. \(cue.speech)"]) }
            return
        }
        if phase == .guiding {
            if let index=guide?.facingPointIndex, let facing=guide?.route.facing(at:index) { read(["그 자리에서 \(facing.label) 방향을 바라봐주세요."]);return }
            if let step=aligningStep { read(["\(step.name)에서 설정된 방향으로 몸을 돌려주세요."]);return }
            if let guide, guide.isHolding {
                read(["공연 대기 중입니다. 다음 지점 안내까지 \(Int(ceil(guide.holdRemaining)))초 남았습니다."]);return
            }
            guard let pose=freshPose(), let guide, let cue=guide.cue(position:pose.point,headingDegrees:pose.heading) else { return }
            read(["\(targetName)으로 이동합니다. \(cue.speech)"]);return
        }
        if phase == .interrupted { read(["안내를 멈췄습니다. 휴대폰을 손에 들고 확인점을 다시 확인해주세요."]);return }
        if phase == .paused { read(["안내를 일시정지했습니다. 현재 위치와 저장된 동선을 확인한 뒤 다시 시작해주세요."]);return }
        if phase == .wear { read([GuidanceCopy.doNotDisturb,"휴대폰을 허리 앞쪽에 세로로 고정해주세요. 후면 카메라는 몸 바깥쪽을 향하고 렌즈는 가리지 말아주세요."]);return }
        if phase == .departure { read([departureStatus]);return }
        read(currentInstruction)
    }
    func read(_ texts: [String], interruptible: Bool = false, after: (()->Void)? = nil) {
        if voiceExperiment, voiceTurnActive {
            // A tracking/audio interruption must not apply an old command to a new recovery step.
            voiceRecognition.discardPendingSpeech();voiceTurnActive=false
        }
        // A reply or question keeps the voice conversation open until it has been heard (#90).
        let answering=voiceExperiment && voiceAwake && phase != .guiding && phase != .starting
        if answering {keepVoiceConversation(120)}
        audioIssue=nil;instructionDone=false;currentInstruction=texts
        voiceNarrationInterruptible=interruptible
        let operation=generation
        voice.play(texts) { [weak self] finished in
            guard let self, finished, self.generation == operation, self.active else { return }
            self.instructionDone=true
            if answering, self.voiceAwake {self.keepVoiceConversation()}
            after?()
        }
    }
    /// Cancels pending speech callbacks; late callbacks see a new generation.
    func invalidateTasks() {
        generation=UUID();voice.stop();instructionDone=false;arrivedName=nil;arrivalShownAt=nil
        signals.stopDirection()
        approachGuide=nil
        escape=nil;quietUntil=nil;signals.setWarning(nil);signals.setWarningQuiet(false)
    }
    /// A pose no older than 0.5 s from a verified session, or nil.
    func freshPose() -> (point: FloorPoint, heading: Double, time: Double)? {
        guard tracking.ready, let p=tracking.position, let heading=tracking.heading, let time=tracking.guidancePoseTime,
              ProcessInfo.processInfo.systemUptime-time >= 0, ProcessInfo.processInfo.systemUptime-time <= 0.5 else { return nil }
        return (FloorPoint(p.x,p.y),heading,time)
    }

    private func tick() {
        guard active else { return }
        captureReplay()
        guard !showExit else { return }
        if phase == .restoring { tickRestoring();return }
        if phase == .checkpoint { tickCheckpoint();return }
        if [.wear,.departure,.starting,.guiding,.paused,.approaching].contains(phase), !tracking.ready {
            interrupt("위치 추적이 끊겼어요. 확인점을 다시 확인해주세요.");return
        }
        if let p=tracking.position, let time=tracking.guidancePoseTime,
           ProcessInfo.processInfo.systemUptime-time >= 0, ProcessInfo.processInfo.systemUptime-time <= 0.5,
           let first=selected?.route?.points.first {
            startDistance=FloorPoint(p.x,p.y).distance(to:first)
        } else { startDistance=nil }
        guard let pose=freshPose() else {
            if phase == .approaching { interrupt("현재 위치와 방향을 확인할 수 없어요. 확인점을 다시 확인해주세요.");return }
            if phase == .departure { departureReady=false;departureGate.reset();readyAnnounced=false }
            if phase == .guiding || phase == .starting { if tracking.heading == nil { interrupt("몸이 향한 방향을 확인할 수 없어요. 착용 방향을 다시 확인해주세요.") } }
            return
        }
        guard pose.time != lastPoseTime else { return }
        lastPoseTime=pose.time;signalPose=pose
        if let first=selected?.route?.points.first { startDistance=pose.point.distance(to:first) }
        if phase == .approaching { tickApproach(pose:pose);return }
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
        if name.hasPrefix("voice_") {VoiceLog.write(name,detail,screen:"guidance.\(phase)")}
        guard let pose=signalPose else { tracking.event(name,detail:detail);return }
        var context=String(format:"x=%.2f y=%.2f heading=%.0f",pose.point.x,pose.point.y,pose.heading)
        // The pose is the last fresh one; say so when tracking has not given a new one since.
        let age=ProcessInfo.processInfo.systemUptime-pose.time
        if age > 0.5 { context+=String(format:" pose_age=%.1fs",age) }
        if let guide, guide.route.points.indices.contains(guide.targetIndex) {
            let target=guide.route.points[guide.targetIndex]
            context+=String(format:" target=p%d(%@) dist=%.2f bearing=%+.0f",guide.targetIndex,
                guide.route.pointLabel(at:guide.targetIndex),pose.point.distance(to:target),
                StageHeading.bearing(from:pose.point,to:target,headingDegrees:pose.heading))
        }
        tracking.event(name,detail:"\(detail) @ \(context) phase=\(phase)")
    }
}
