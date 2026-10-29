import Foundation
import HearIAmCore

/// 4 / 4 · 출발 준비: the wearer must hold a valid start (or resume) pose for one second.
extension GuidanceViewModel {
    var departureStatus: String {
        guard let pose=freshPose(), let guide else {
            return tracking.heading == nil ? "카메라가 바닥이나 천장을 향하지 않도록 허리 앞쪽에 세워주세요." : "현재 위치를 다시 확인하고 있어요."
        }
        if !started, pose.point.distance(to:guide.route.points[0]) > guide.settings.startRadius {
            return approachIssue ?? "출발점까지 안내 버튼을 눌러 이동해주세요."
        }
        if guide.pausesForPositionIssues, let issue=guide.positionIssue(pose.point) {
            return issue == .obstacleProximity ? "등록한 기물과 가까워요. 출발 위치와 동선을 확인해주세요." : "저장한 동선 위에 서주세요."
        }
        return departureReady ? "위치와 몸의 방향이 확인됐어요." : "위치와 방향을 확인 중이에요. 잠시 멈춰주세요."
    }
    /// Starts from departure, or resumes from a pause, after the start announcement finishes.
    func startGuidance() {
        guard (phase == .departure && departureReady || phase == .paused && canResume), canAdvanceInstruction, active else { return }
        let pendingStep=aligningStep
        invalidateTasks()
        phase = .starting
        let resumingHold=guide?.isHolding == true
        let pendingFacing=guide?.facingPointIndex
        let lines: [String]
        if pendingFacing != nil { lines=["바라볼 방향 안내를 이어갑니다."] }
        else if !started, guide?.route.facing(at:0) != nil { lines=["안내를 시작합니다. 출발점에서 바라볼 방향을 먼저 맞춥니다."] }
        else if resumingHold { lines=["공연 대기를 이어갑니다."] }
        else { lines=[started ? "안내를 다시 시작합니다." : "안내를 시작합니다.",SignalCopy.start] }
        read(lines) { [weak self] in
            guard let self, self.phase == .starting, var guide=self.guide else { return }
            guard let pose=self.freshPose() else { self.interrupt("현재 위치를 확인할 수 없어요. 확인점을 다시 확인해주세요.");return }
            let first = !self.started
            let success=self.started ? guide.resume(position:pose.point,trackingValid:true) : guide.start(position:pose.point,headingDegrees:pose.heading,trackingValid:true)
            guard success else {
                self.phase = .departure;self.departureReady=false;self.departureGate.reset();self.readyAnnounced=false
                self.read(["출발 조건이 달라졌습니다. 위치와 방향을 다시 확인해주세요."]);return
            }
            self.guide=guide;self.run?.begin(at:Date(),uptime:ProcessInfo.processInfo.systemUptime);self.started=true;self.phase = .guiding;self.lastPoseTime=nil
            self.resetSignals();self.performanceHoldRemaining=guide.holdRemaining
            if let pendingStep { self.aligningStep=pendingStep;self.announceNextSide=true }
            // The start has no ding of its own here (it rang on settling), so the side comes on the first cue.
            if let index=guide.facingPointIndex, let facing=guide.route.facing(at:index) {
                self.read(["그 자리에서 \(facing.label) 방향을 바라봐주세요."])
            }
            if first {
                self.announceNextSide=true
                self.announceStepHint=guide.route.step(at:guide.targetIndex) != nil
            }
        }
    }
    func tickDeparture(pose: (point: FloorPoint, heading: Double, time: Double), guide: RouteGuide) {
        let eligible=started ? guide.canResume(position:pose.point,trackingValid:true) : guide.ready(position:pose.point,headingDegrees:pose.heading,trackingValid:true)
        let wasReady=departureReady
        departureReady=departureGate.observe(time:pose.time,eligible:eligible)
        // The start is a point too: ding once the wearer has settled on it (10/19).
        if departureReady, !wasReady, !started {
            signals.play(.arrival);logSignal("signal_arrival","\(GuidanceCopy.target(0,last:guide.route.points.count-1)) ready")
        }
        if !eligible {
            if readyAnnounced {read(["출발 위치 또는 방향이 달라졌습니다. 다시 확인해주세요."])}
            readyAnnounced=false
        }
        if departureReady, !readyAnnounced, instructionDone, !speaking {
            readyAnnounced=true
            read([started ? "재개 준비가 완료됐습니다. 안내 다시 시작 버튼을 눌러주세요." : "출발 준비가 완료됐습니다. 안내 시작 버튼을 눌러주세요."])
        }
    }

    var approachIssue: String? {
        guard !started, let pose=freshPose(), let guide else { return "현재 위치와 몸의 방향을 확인해주세요." }
        do { _=try StartApproach.route(from:pose.point,to:guide.route,settings:guide.settings);return nil }
        catch { return error.localizedDescription }
    }
    var canApproachStart: Bool { !started && phase == .departure && approachIssue == nil }
    func startApproach() {
        guard canApproachStart, canAdvanceInstruction, active else { return }
        invalidateTasks();resetSignals();phase = .approaching;cue=nil
        tracking.setGuidanceTarget(0)
        read(["출발점까지 안내합니다. 방향과 거리를 듣고 이동해주세요."]) { [weak self] in
            guard let self, self.phase == .approaching else { return }
            guard let pose=self.freshPose(), let saved=self.guide else {
                self.interrupt("현재 위치를 확인할 수 없어요. 확인점을 다시 확인해주세요.");return
            }
            do {
                let route=try StartApproach.route(from:pose.point,to:saved.route,settings:saved.settings)
                var approach=RouteGuide(route:route,settings:saved.settings,usesRouteCorridor:true)
                guard approach.start(position:pose.point,headingDegrees:pose.heading,trackingValid:true) else { throw LabError.invalid("출발 위치를 다시 확인해주세요.") }
                self.approachGuide=approach;self.announceNextSide=true;self.lastPoseTime=nil
            } catch { self.stopApproach(error.localizedDescription) }
        }
    }
    func tickApproach(pose: (point: FloorPoint, heading: Double, time: Double)) {
        guard var approach=approachGuide else { return }
        let result=approach.observe(time:pose.time,position:pose.point,headingDegrees:pose.heading,trackingValid:true)
        approachGuide=approach
        cue=approach.cue(position:pose.point,headingDegrees:pose.heading)
        if result.state == .completed {
            stopApproach("출발점에 도착했습니다. 잠시 멈춘 뒤 안내 시작 버튼을 눌러주세요.")
        } else if result.state == .paused {
            stopApproach("잠시 멈춰주세요. 출발점 접근 경로를 벗어났거나 위치 확인이 중단됐어요. 현재 위치와 기물을 확인한 뒤 다시 시작해주세요.")
        } else { signal(pose:pose,guide:approach) }
    }
    func stopApproach(_ text: String) {
        invalidateTasks();resetSignals();cue=nil;phase = .departure
        departureReady=false;departureGate.reset();readyAnnounced=false;lastPoseTime=nil
        read([text])
    }
}
