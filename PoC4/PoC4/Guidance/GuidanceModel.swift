import SwiftUI
import Combine
import AVFoundation
import PoC4Core

@MainActor final class GuidanceModel: ObservableObject {
    enum Phase { case selection, restoring, checkpoint, wear, countdown, departure, starting, guiding, paused, interrupted, failed, finishing, completed }
    @Published private(set) var phase: Phase = .selection {
        didSet { run?.setRunning(phase == .guiding,uptime:ProcessInfo.processInfo.systemUptime) }
    }
    @Published private(set) var selected: ScanManifest?
    @Published private(set) var instructionDone=false
    @Published private(set) var speaking=false
    @Published private(set) var spokenText=""
    @Published private(set) var audioIssue: String?
    @Published private(set) var message=""
    @Published private(set) var countdown=8
    @Published private(set) var departureReady=false
    @Published private(set) var startDistance: Double?
    @Published private(set) var cue: GuidanceCue?
    @Published private(set) var arrivedName: String?
    @Published var showExit=false
    let tracking=ScanLabModel(guidanceSession:true)
    private let voice=GuidanceSpeech()
    private var guide: RouteGuide?
    private var run: GuidanceRun?
    private var pendingRecord: GuidanceRecord?
    private var departureGate=DepartureGate()
    private var readyAnnounced=false
    private var lastPoseTime: Double?
    private var timer: Timer?
    private var countdownTask: Task<Void,Never>?
    private var generation=UUID()
    private var active=true
    private var started=false
    private var announcingArrival=false
    private var observations: [NSObjectProtocol]=[]
    private var trackingSubscription: AnyCancellable?
    private var currentInstruction: [String]=[]
    var hasStarted: Bool { started }
    var targetIndex: Int { guide?.targetIndex ?? 1 }
    var targetName: String { GuidanceCopy.target(targetIndex,last:(selected?.route?.points.count ?? 2)-1) }
    var showsRouteCamera: Bool { [.starting,.guiding,.paused,.finishing,.completed].contains(phase) }
    var isCameraStep: Bool { phase == .restoring || phase == .checkpoint }
    var departureStatus: String {
        guard let pose=freshPose(), let guide else {
            return tracking.heading == nil ? "카메라가 바닥이나 천장을 향하지 않도록 허리 앞쪽에 세워주세요." : "현재 위치를 다시 확인하고 있어요."
        }
        if !started, pose.point.distance(to:guide.route.points[0]) > guide.settings.startRadius {
            return "지정한 출발점에 더 가까이 서주세요."
        }
        if let issue=guide.positionIssue(pose.point) {
            return issue == .obstacleProximity ? "등록한 기물과 가까워요. 출발 위치와 동선을 확인해주세요." : "저장한 동선 위에 서주세요."
        }
        return departureReady ? "위치와 몸의 방향이 확인됐어요." : "위치와 방향을 확인 중이에요. 잠시 멈춰주세요."
    }
    var canVerify: Bool { phase == .checkpoint && instructionDone && tracking.canVerify && !speaking }
    var canResume: Bool {
        guard let pose=freshPose(), let guide else { return false }
        return guide.canResume(position:pose.point,trackingValid:true)
    }

    init() {
        tracking.showMesh=false
        trackingSubscription=tracking.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        voice.onSpeaking={ [weak self] in self?.speaking=$0 }
        voice.onText={ [weak self] in self?.spokenText=$0 }
        voice.onError={ [weak self] text in
            guard let self else { return }
            self.audioIssue=text;self.instructionDone=false
            if self.phase == .guiding || self.phase == .starting {
                self.guide?.pause();self.phase = self.started ? .paused : .departure;self.message="음성 재생을 확인한 후 다시 시작해주세요."
            }
        }
        observations.append(NotificationCenter.default.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) { [weak self] n in
            guard let raw=n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue:raw) == .began else { return }
            Task { @MainActor in
                self?.voice.audioWasInterrupted()
                self?.interrupt("음성 재생이 중단됐어요. 확인점과 착용 상태를 다시 확인해주세요.",announce:false)
            }
        })
        observations.append(NotificationCenter.default.addObserver(forName:AVAudioSession.routeChangeNotification,object:nil,queue:.main) { [weak self] n in
            guard let raw=n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue:raw) == .oldDeviceUnavailable else { return }
            Task { @MainActor in self?.interrupt("소리 출력이 변경됐어요. 확인점과 착용 상태를 다시 확인해주세요.") }
        })
        timer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    deinit {
        timer?.invalidate();countdownTask?.cancel()
        observations.forEach {NotificationCenter.default.removeObserver($0)}
    }

    func selectionDescription(empty: Bool) {
        guard phase == .selection else { return }
        read([empty ? "저장된 무대가 없습니다. 홈에서 무대 준비하기를 통해 공간과 동선을 먼저 저장해주세요." : "안내에 사용할 무대를 선택해주세요."])
    }
    func select(_ item: ScanManifest) {
        guard phase == .selection else { return }
        guard let route=item.route, route.conflicts(boundaryMargin:item.settings.boundaryMargin,obstacleClearance:item.settings.obstacleClearance).isEmpty else {
            read(["이 무대에는 사용할 수 있는 동선이 없습니다. 무대를 다시 준비해주세요."]);return
        }
        selected=item;guide=RouteGuide(route:route,settings:item.settings,usesRouteCorridor:true)
        started=false;cue=nil;pendingRecord=nil
        run=GuidanceRun(stageID:item.id,stageName:item.name,route:route)
        tracking.setGuidanceTarget(1)
        read(["\(item.name)을 선택했습니다. 내부 지점은 \(max(0,route.points.count-2))개입니다."])
    }
    func restore() {
        guard let selected, active, !tracking.busy else { return }
        invalidateTasks();departureReady=false;departureGate.reset();readyAnnounced=false;lastPoseTime=nil
        tracking.endSession();tracking.setActive(true);tracking.errorMessage=nil
        message="저장한 공연장 위치를 확인하고 있어요."
        phase = .restoring
        read(["저장한 공연장을 확인할게요. 휴대폰을 손에 들고 주변을 천천히 비춰주세요."])
        tracking.restore(selected)
    }
    func chooseAgain() {
        invalidateTasks();tracking.endSession();guide=nil;run=nil;pendingRecord=nil;selected=nil;started=false;phase = .selection
        read(["안내에 사용할 무대를 다시 선택해주세요."])
    }
    func verifyCheckpoint() {
        guard canVerify else { return }
        tracking.errorMessage=nil;tracking.verifyCheckpoint()
        if tracking.ready {
            phase = .wear;message="확인점이 일치합니다."
            read(["확인점이 일치합니다.","휴대폰을 허리 앞쪽에 세로로 고정해주세요. 후면 카메라는 몸 바깥쪽을 향하고 렌즈는 가리지 말아주세요."])
        } else {
            message=tracking.errorMessage ?? "저장된 확인점과 위치가 맞지 않아요."
            read(["\(message) 확인점을 다시 비춰주세요."])
        }
    }
    func beginWear() {
        guard phase == .wear || phase == .countdown, tracking.ready, active else { return }
        invalidateTasks();phase = .countdown;countdown=8
        let operation=generation
        read(["지금부터 8초 동안 착용해주세요. 마지막 3초를 알려드릴게요."]) { [weak self] in
            guard let self, self.generation == operation else { return }
            self.countdownTask=Task { [weak self] in
                guard let self else { return }
                for remaining in stride(from:8,through:1,by:-1) {
                    guard !Task.isCancelled, self.generation == operation, self.active, self.tracking.ready else { return }
                    self.countdown=remaining
                    let began=ProcessInfo.processInfo.systemUptime
                    if remaining <= 3 {
                        let finished=await withCheckedContinuation { continuation in
                            self.voice.play([String(remaining)]) { continuation.resume(returning:$0) }
                        }
                        guard finished, !Task.isCancelled, self.generation == operation else { return }
                    }
                    let delay=max(0,1-(ProcessInfo.processInfo.systemUptime-began))
                    do { try await Task.sleep(nanoseconds:UInt64(delay*1_000_000_000)) } catch { return }
                }
                guard self.generation == operation, self.active, self.tracking.ready else { return }
                self.phase = .departure;self.countdownTask=nil;self.departureGate.reset();self.readyAnnounced=false
                self.read([self.started ? "착용 상태를 확인하고 있습니다. 안내를 중단한 동선 위에서 준비해주세요." : "착용 상태를 확인하고 있습니다. 지정한 출발점에서 잠시 멈춰주세요. 몸이 향한 방향을 기준으로 안내합니다."])
            }
        }
    }
    func startGuidance() {
        guard (phase == .departure && departureReady || phase == .paused && canResume), instructionDone, !speaking else { return }
        phase = .starting
        read([started ? "안내를 다시 시작합니다." : "안내를 시작합니다.","\(targetName)으로 이동합니다."]) { [weak self] in
            guard let self, self.phase == .starting, var guide=self.guide else { return }
            guard let pose=self.freshPose() else { self.interrupt("현재 위치를 확인할 수 없어요. 확인점을 다시 확인해주세요.");return }
            let success=self.started ? guide.resume(position:pose.point,trackingValid:true) : guide.start(position:pose.point,headingDegrees:pose.heading,trackingValid:true)
            guard success else {
                self.phase = .departure;self.departureReady=false;self.departureGate.reset();self.readyAnnounced=false
                self.read(["출발 조건이 달라졌습니다. 위치와 방향을 다시 확인해주세요."]);return
            }
            self.guide=guide;self.run?.begin(at:Date(),uptime:ProcessInfo.processInfo.systemUptime);self.started=true;self.phase = .guiding;self.lastPoseTime=nil;self.announcingArrival=false
        }
    }
    func pause() {
        guard phase == .guiding || phase == .starting else { return }
        invalidateTasks();guide?.pause();phase = started ? .paused : .departure
        message="현재 목표는 \(targetName)이에요."
        read(["안내를 일시정지했습니다. 다시 시작 버튼을 누르면 이어서 안내합니다."])
    }
    func requestExit() {
        guard phase != .finishing else { return }
        if phase == .guiding || phase == .starting { guide?.pause();phase = started ? .paused : .departure }
        if phase == .countdown { phase = .wear }
        invalidateTasks();showExit=true
        read(["안내를 끝낼까요? 계속 사용하려면 계속 사용하기를 눌러주세요."])
    }
    func cancelExit() { showExit=false;replay() }
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
    func setActive(_ value: Bool) {
        guard active != value else { return };active=value
        if !value {
            interrupt("앱이 중단됐어요. 확인점과 착용 상태를 다시 확인해주세요.",announce:false)
            tracking.setActive(false)
        } else {
            tracking.setActive(true)
            if phase == .interrupted { read(["안내를 멈췄습니다. 휴대폰을 손에 들고 확인점을 다시 확인해주세요."]) }
            else if phase == .selection { replay() }
        }
    }
    func completedRecord() throws -> GuidanceRecord {
        guard phase == .completed, guide?.state == .completed, let run else {
            throw LabError.invalid("마지막 도착 안내가 끝난 후 종료해주세요.")
        }
        if let pendingRecord { return pendingRecord }
        let record=try run.record(completionSpoken:true,finishedAt:Date())
        pendingRecord=record;return record
    }
    func finish() {
        active=false;invalidateTasks();timer?.invalidate();timer=nil
        observations.forEach {NotificationCenter.default.removeObserver($0)};observations=[]
        tracking.endSession();voice.deactivate()
    }

    private func read(_ texts: [String], after: (()->Void)? = nil) {
        audioIssue=nil;instructionDone=false;currentInstruction=texts
        let operation=generation
        voice.play(texts) { [weak self] finished in
            guard let self, finished, self.generation == operation, self.active else { return }
            self.instructionDone=true;after?()
        }
    }
    private func invalidateTasks() {
        generation=UUID();countdownTask?.cancel();countdownTask=nil;voice.stop();instructionDone=false;announcingArrival=false;arrivedName=nil
    }
    private func interrupt(_ reason: String, announce: Bool = true) {
        if phase == .completed { return }
        invalidateTasks()
        if phase == .finishing { message="종료 음성이 중단됐어요. 다시 들은 뒤 종료해주세요.";return }
        if phase == .selection { return }
        guide?.pause();phase = .interrupted;departureReady=false;departureGate.reset();message=reason
        tracking.endSession()
        if announce && active { read(["위치 또는 소리를 확인할 수 없어 안내를 멈췄습니다. 잠시 멈춰주세요. 휴대폰을 손에 들고 확인점을 다시 확인해주세요."]) }
    }
    private func freshPose() -> (point: FloorPoint, heading: Double, time: Double)? {
        guard tracking.ready, let p=tracking.position, let heading=tracking.heading, let time=tracking.guidancePoseTime,
              ProcessInfo.processInfo.systemUptime-time >= 0, ProcessInfo.processInfo.systemUptime-time <= 0.5 else { return nil }
        return (FloorPoint(p.x,p.y),heading,time)
    }
    private func tick() {
        guard active, !showExit else { return }
        if phase == .restoring {
            if let error=tracking.errorMessage { fail(error);return }
            if !tracking.busy && tracking.mode == .idle { fail(tracking.status);return }
            if tracking.canVerify, instructionDone, !speaking {
                phase = .checkpoint;message="중앙 조준점을 저장한 확인점에 맞춰주세요."
                read(["공연장을 찾았습니다. 저장한 확인점에 중앙 조준점을 맞춘 뒤 확인점 확인하기를 눌러주세요."])
            }
            return
        }
        if phase == .checkpoint {
            if tracking.mode == .idle { fail(tracking.status) }
            return
        }
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
        lastPoseTime=pose.time
        if let first=selected?.route?.points.first { startDistance=pose.point.distance(to:first) }
        if phase == .departure, let guide {
            let eligible=started ? guide.canResume(position:pose.point,trackingValid:true) : guide.ready(position:pose.point,headingDegrees:pose.heading,trackingValid:true)
            departureReady=departureGate.observe(time:pose.time,eligible:eligible)
            if !eligible {
                if readyAnnounced {read(["출발 위치 또는 방향이 달라졌습니다. 다시 확인해주세요."])}
                readyAnnounced=false
            }
            if departureReady, !readyAnnounced, instructionDone, !speaking {
                readyAnnounced=true
                read([started ? "재개 준비가 완료됐습니다. 안내 다시 시작 버튼을 눌러주세요." : "출발 준비가 완료됐습니다. 안내 시작 버튼을 누르면 첫 번째 지점으로 안내합니다."])
            }
            return
        }
        guard phase == .guiding, var guide else { return }
        let previous=guide.targetIndex
        let update=guide.observe(time:pose.time,position:pose.point,headingDegrees:pose.heading,trackingValid:true,allowsTargetAdvance:!announcingArrival)
        self.guide=guide;cue=guide.cue(position:pose.point,headingDegrees:pose.heading)
        tracking.setGuidanceTarget(guide.targetIndex,completed:guide.state == .completed)
        if update.state == .completed { playCompletion();return }
        if update.state == .paused {
            phase = .paused
            switch guide.pauseReason {
            case .obstacleProximity: message="등록한 기물과 가까워졌어요. 현재 위치와 동선을 확인해주세요."
            case .offRoute,.outsideStage: message="저장된 동선의 안내 범위를 벗어났어요. 현재 위치와 동선을 확인해주세요."
            default: message="위치와 방향을 다시 확인해주세요."
            }
            read(["잠시 멈춰주세요. \(message)"]);return
        }
        if update.targetIndex != previous {
            let previousName=GuidanceCopy.target(previous,last:guide.route.points.count-1)
            announcingArrival=true;arrivedName=previousName
            read(["\(previousName)에 도착했습니다. \(targetName)으로 이동합니다."]) { [weak self] in
                guard let self, self.phase == .guiding else { return }
                self.announcingArrival=false;self.arrivedName=nil
                if let pose=self.freshPose(), let cue=self.guide?.cue(position:pose.point,headingDegrees:pose.heading) {
                    self.voice.direction(cue.speech)
                }
            }
        } else if let announcement=update.announcement { voice.direction(announcement) }
    }
    private func playCompletion() {
        guard phase != .finishing || !speaking else { return }
        if let guide { run?.arrive(guide:guide,at:Date(),uptime:ProcessInfo.processInfo.systemUptime) }
        invalidateTasks();phase = .finishing;cue=nil;message="종료 안내를 읽고 있어요."
        // Guidance stops now; the validation camera stays live until the user finishes.
        audioIssue=nil
        let operation=generation
        voice.play([GuidanceCopy.completed],final:true) { [weak self] finished in
            guard let self, finished, self.generation == operation, self.active else { return }
            self.phase = .completed;self.instructionDone=true;self.message="출발부터 마지막 지점까지 안내를 완료했어요."
        }
    }
    private func fail(_ error: String) {
        phase = .failed;message=error;tracking.endSession()
        read(["공연장을 확인하지 못했습니다. \(error) 다시 시도해주세요."])
    }
}
