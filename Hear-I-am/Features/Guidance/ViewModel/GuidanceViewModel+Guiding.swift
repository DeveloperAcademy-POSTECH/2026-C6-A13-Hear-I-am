import HearIAmCore

/// #48: body-relative rising (left) / falling (right) mono glides and a latched double beep.
/// Speech, obstacle warnings and the arrival ding take priority over direction sounds.
extension GuidanceViewModel {
    static let arrivalShownSeconds=2.0, arrivalWarningPause=1.5, arrivalDirectionPause=0.7

    var canResume: Bool {
        guard let pose=freshPose(), let guide else { return false }
        return guide.canResume(position:pose.point,trackingValid:true)
    }
    func pause() {
        guard phase == .guiding || phase == .starting else { return }
        invalidateTasks();guide?.pause();phase = started ? .paused : .departure
        message="현재 목표는 \(targetName)이에요."
        read(["안내를 일시정지했습니다. 다시 시작 버튼을 누르면 이어서 안내합니다."])
    }
    /// Clears every signal rule; called when guidance starts or resumes.
    func resetSignals() {
        directionSweep.reset();warnings.reset();steps.reset();arrivalShownAt=nil;warningHoldUntil=nil
        signals.stop()
    }
    func tickGuiding(pose: (point: FloorPoint, heading: Double, time: Double), guide current: RouteGuide) {
        var guide=current
        let previous=guide.targetIndex
        let update=guide.observe(time:pose.time,position:pose.point,headingDegrees:pose.heading,trackingValid:true)
        self.guide=guide;cue=guide.cue(position:pose.point,headingDegrees:pose.heading)
        tracking.setGuidanceTarget(guide.targetIndex,completed:guide.state == .completed)
        if update.state == .completed { playCompletion();return }
        if update.state == .paused {
            if let reason=guide.pauseReason, Self.escapeReasons.contains(reason) { beginEscape(reason:reason,pose:pose,guide:guide) }
            else { paused(guide:guide) }
            return
        }
        if update.targetIndex != previous { arrived(previous,guide:guide,time:pose.time) }
        if let shown=arrivalShownAt, pose.time-shown > Self.arrivalShownSeconds { arrivedName=nil;arrivalShownAt=nil }
        signal(pose:pose,guide:guide)
    }

    /// The next target starts a new direction-alignment cycle after the arrival ding finishes.
    private func arrived(_ previous: Int, guide: RouteGuide, time: Double) {
        let name=GuidanceCopy.target(previous,last:guide.route.points.count-1)
        arrivedName=name;arrivalShownAt=time
        directionSweep.reset();signals.stopDirection()
        signals.setWarning(nil);warningHoldUntil=time+Self.arrivalWarningPause
        signals.play(.arrival)
        tracking.event("signal_arrival",detail:"\(name) next=\(guide.targetIndex)")
    }
    private func signal(pose: (point: FloorPoint, heading: Double, time: Double), guide: RouteGuide) {
        guard guide.route.points.indices.contains(guide.targetIndex) else { return }
        let target=guide.route.points[guide.targetIndex]
        let bearing=StageHeading.bearing(from:pose.point,to:target,headingDegrees:pose.heading)
        if let hold=warningHoldUntil, pose.time < hold {} else {
            warningHoldUntil=nil
            let warning=warnings.update(position:pose.point,headingDegrees:pose.heading,obstacles:guide.route.obstacles)
            if warning?.level != signals.warning {
                signals.setWarning(warning?.level)
                tracking.event("signal_warning_reason",detail:warning?.detail ?? "off")
            }
        }
        guard phase == .guiding, audioIssue == nil else { return }
        if let step=steps.update(position:pose.point,target:target,obstacles:guide.route.obstacles) {
            voice.play([step.line]);tracking.event("signal_step",detail:step.detail)
        }
        guard phase == .guiding, audioIssue == nil else { return }
        // Within arrival radius, the target bearing is unstable and arrival dwell owns the feedback.
        if pose.point.distance(to:target) <= guide.settings.arrivalRadius ||
            arrivalShownAt.map({pose.time-$0 < Self.arrivalDirectionPause}) == true {
            suspendDirection();return
        }
        updateDirection(bearing:bearing,time:pose.time,context:"route target=\(guide.targetIndex)")
    }
    func suspendDirection() {
        directionSweep.suspend();signals.stopDirection()
    }
    /// Shared by normal travel and recovery; the caller supplies the appropriate destination.
    func updateDirection(bearing: Double, time: Double, context: String) {
        guard !speaking, audioIssue == nil, signals.warning == nil else { suspendDirection();return }
        let update=directionSweep.update(time:time,bearing:bearing)
        if update.stopPrevious { signals.stopDirection() }
        if let sound=update.sound {
            if signals.play(sound) {
                tracking.event("signal_sweep_reason",detail:String(format:"%@ bearing=%+.1f %@",context,bearing,sound.name))
            } else { directionSweep.reset() }
        }
    }
    private func paused(guide: RouteGuide) {
        directionSweep.reset();signals.stop()
        phase = .paused
        switch guide.pauseReason {
        case .obstacleProximity: message="등록한 기물과 가까워졌어요. 현재 위치와 동선을 확인해주세요."
        case .offRoute,.outsideStage: message="저장된 동선의 안내 범위를 벗어났어요. 현재 위치와 동선을 확인해주세요."
        default: message="위치와 방향을 다시 확인해주세요."
        }
        read(["잠시 멈춰주세요. \(message)"])
    }
}
