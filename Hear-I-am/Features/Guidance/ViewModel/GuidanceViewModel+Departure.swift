import Foundation
import HearIAmCore

/// 4 / 4 · 출발 준비: the wearer must hold a valid start (or resume) pose for one second.
extension GuidanceViewModel {
    var departureStatus: String {
        if !started, let approachNotice { return approachNotice }
        guard let pose=freshPose(), let guide else {
            return tracking.heading == nil ? "카메라가 바닥이나 천장을 향하지 않도록 허리 앞쪽에 세워주세요." : "현재 위치를 다시 확인하고 있어요."
        }
        if !started, pose.point.distance(to:guide.route.points[0]) > guide.settings.startRadius {
            return "출발점까지 안내 버튼을 눌러 이동해주세요. 무대 안팎의 스캔한 공간에서 접근할 수 있어요."
        }
        if guide.pausesForPositionIssues, let issue=guide.positionIssue(pose.point) {
            return issue == .obstacleProximity ? "등록한 기물과 가까워요. 출발 위치와 동선을 확인해주세요." : "저장한 동선 위에 서주세요."
        }
        return departureReady ? "위치와 몸의 방향이 확인됐어요." : "위치와 방향을 확인 중이에요. 잠시 멈춰주세요."
    }
    /// Starts from departure, or resumes from a pause, after the start announcement finishes.
    func startGuidance(automatically: Bool = false) {
        guard (phase == .departure && departureReady || phase == .paused && canResume), canAdvanceInstruction, active else { return }
        if !started {
            guard startAlignmentCompleted, let pose=freshPose(), matchesStart(pose) else {
                departureReady=false;startAlignmentCompleted=false;return
            }
        }
        let pendingStep=aligningStep
        let resumingFacing=guide?.facingPointIndex != nil
        let resumingHold=guide?.isHolding == true
        let lines=resumingHold ? ["공연 대기를 이어갑니다."] : [started ? "안내를 다시 시작합니다." : "안내를 시작합니다.",SignalCopy.start]
        invalidateTasks();phase = .starting
        let begin: () -> Void = { [weak self] in
            guard let self, self.phase == .starting, var guide=self.guide else { return }
            guard let pose=self.freshPose() else { self.interrupt("현재 위치를 확인할 수 없어요. 확인점을 다시 확인해주세요.");return }
            let first = !self.started
            if first && !self.matchesStart(pose) {
                self.phase = .departure;self.departureReady=false;self.startAlignmentCompleted=false
                self.departureGate.reset();self.readyAnnounced=false;return
            }
            let success=self.started ? guide.resume(position:pose.point,trackingValid:true) : guide.start(position:pose.point,headingDegrees:pose.heading,trackingValid:true)
            guard success else {
                self.phase = .departure;self.departureReady=false;self.departureGate.reset();self.readyAnnounced=false
                self.read(["출발 조건이 달라졌습니다. 위치와 방향을 다시 확인해주세요."]);return
            }
            self.guide=guide;self.run?.begin(at:Date(),uptime:ProcessInfo.processInfo.systemUptime);self.started=true;self.phase = .guiding;self.lastPoseTime=nil
            self.resetSignals();self.performanceHoldRemaining=guide.holdRemaining
            if let pendingStep { self.aligningStep=pendingStep;self.announceNextSide=true }
            if resumingFacing { self.announceNextSide=true }
            if first {
                self.announceNextSide=true
                self.announceStepHint=guide.route.step(at:guide.targetIndex) != nil
                if automatically { self.read([SignalCopy.start]) }
            }
        }
        if automatically || resumingFacing { begin() } else { read(lines,after:begin) }
    }
    private func matchesStart(_ pose: (point: FloorPoint, heading: Double, time: Double)) -> Bool {
        guard let guide, let alignment=try? StartAlignment(route:guide.route,settings:guide.settings) else { return false }
        return alignment.matches(position:pose.point,headingDegrees:pose.heading)
    }
    func tickDeparture(pose: (point: FloorPoint, heading: Double, time: Double), guide: RouteGuide) {
        if !started {
            if !matchesStart(pose) { startAlignmentCompleted=false }
            if !startAlignmentCompleted {
                departureReady=false;departureGate.reset();readyAnnounced=false
                if !startPreparationPaused, pose.point.distance(to:guide.route.points[0]) <= guide.settings.startRadius { beginStartAlignment() }
                return
            }
            departureReady=guide.ready(position:pose.point,headingDegrees:pose.heading,trackingValid:true)
            return
        }
        let eligible=started ? guide.canResume(position:pose.point,trackingValid:true) : guide.ready(position:pose.point,headingDegrees:pose.heading,trackingValid:true)
        departureReady=departureGate.observe(time:pose.time,eligible:eligible)

        if !eligible {
            if readyAnnounced {read(["출발 위치 또는 방향이 달라졌습니다. 다시 확인해주세요."])}
            readyAnnounced=false
        }
        if departureReady, !readyAnnounced, instructionDone, !speaking {
            readyAnnounced=true
            read([started ? "재개 준비가 완료됐습니다. 안내 다시 시작 버튼을 눌러주세요." : "출발 준비가 완료됐습니다. 안내 시작 버튼을 눌러주세요."])
        }
    }

    /// Availability is separate from route eligibility: a tap must be able to explain why guidance cannot start.
    var canApproachStart: Bool { !started && phase == .departure && guide != nil && active }
    func startApproach() {
        guard canApproachStart, canAdvanceInstruction else { return }
        // Stop the wear/departure explanation immediately, even when the pose is not usable yet.
        invalidateTasks();resetSignals();cue=nil;approachNotice=nil
        guard let pose=freshPose(), let saved=guide else {
            explainApproachIssue("현재 위치와 몸의 방향을 확인 중이에요. 휴대폰을 허리 앞쪽에 세우고 잠시 후 다시 눌러주세요.")
            return
        }
        startPreparationPaused=false;startAlignmentCompleted=false
        if pose.point.distance(to:saved.route.points[0]) <= saved.settings.startRadius { beginStartAlignment();return }
        guard let footprint=tracking.scannedFootprint else {
            explainApproachIssue("저장된 LiDAR 스캔에서 접근 범위를 확인할 수 없어요. 출발점 주변 바닥까지 스캔했는지 확인해주세요.")
            return
        }
        do {
            let route=try StartApproach.route(from:pose.point,to:saved.route,settings:saved.settings,footprint:footprint)
            var approach=RouteGuide(route:route,settings:saved.settings,usesRouteCorridor:true,approachFootprint:footprint)
            guard approach.start(position:pose.point,headingDegrees:pose.heading,trackingValid:true) else {
                throw LabError.invalid("출발 위치를 다시 확인해주세요.")
            }
            approachGuide=approach;announceNextSide=true;lastPoseTime=nil
            phase = .approaching;tracking.setGuidanceTarget(0)
            read(["출발점까지 안내합니다."])
        } catch {
            explainApproachIssue(error.localizedDescription)
        }
    }
    private func explainApproachIssue(_ text: String) {
        approachNotice=text;logSignal("start_approach_unavailable",text);read([text])
    }
    func tickApproach(pose: (point: FloorPoint, heading: Double, time: Double)) {
        if startAlignment != nil { tickStartAlignment(pose:pose);return }
        guard var approach=approachGuide else { return }
        let result=approach.observe(time:pose.time,position:pose.point,headingDegrees:pose.heading,trackingValid:true)
        approachGuide=approach
        cue=approach.cue(position:pose.point,headingDegrees:pose.heading)
        if result.state == .completed {
            beginStartAlignment()
        } else if result.state == .paused {
            stopApproach("잠시 멈춰주세요. LiDAR 스캔 범위나 접근 경로를 벗어났거나 위치 확인이 중단됐어요. 현재 위치와 기물을 확인한 뒤 다시 시작해주세요.")
        } else { signal(pose:pose,guide:approach) }
    }
    func stopApproach(_ text: String) {
        startPreparationPaused=true;startAlignmentCompleted=false;approachNotice=text
        invalidateTasks();resetSignals();cue=nil;phase = .departure
        departureReady=false;departureGate.reset();readyAnnounced=false;lastPoseTime=nil
        read([text])
    }
    private func beginStartAlignment() {
        guard !started, let guide else { return }
        do {
            let alignment=try StartAlignment(route:guide.route,settings:guide.settings)
            invalidateTasks();resetSignals();cue=nil;approachNotice=nil
            startPreparationPaused=false;startAlignmentCompleted=false;departureReady=false
            startAlignment=alignment;phase = .approaching;tracking.setGuidanceTarget(0)
            announceNextSide=true;lastPoseTime=nil
            read(["출발점 도착"])
        } catch { stopApproach(error.localizedDescription) }
    }
    private func tickStartAlignment(pose: (point: FloorPoint, heading: Double, time: Double)) {
        guard var alignment=startAlignment, let guide else { return }
        let previous=alignment.state
        alignment.observe(time:pose.time,position:pose.point,headingDegrees:pose.heading,trackingValid:true,allowsAdvance:!speaking && audioIssue == nil)
        startAlignment=alignment
        switch alignment.state {
        case .paused:
            stopApproach("잠시 멈춰주세요. 출발 위치와 방향을 다시 확인한 뒤 출발점 안내를 눌러주세요.")
        case .aligning:
            if previous == .waiting { directionTicks.reset();announceNextSide=true }
            signalStartFacing(pose:pose,bearing:alignment.bearing(headingDegrees:pose.heading),guide:guide)
        case .waiting:
            if previous == .aligning { signals.playAligned();directionTicks.reset() }
        case .ready:
            startAlignment=nil;approachGuide=nil;startAlignmentCompleted=true
            phase = .departure;departureReady=true;readyAnnounced=true;departureGate.reset();lastPoseTime=nil
            if alignment.automaticallyStarts { startGuidance(automatically:true) }
            else { read(["안내 시작 버튼을 눌러주세요."]) }
            if previous == .aligning, audioIssue == nil, phase == .guiding || phase == .departure { signals.playAligned() }
        }
    }

}
