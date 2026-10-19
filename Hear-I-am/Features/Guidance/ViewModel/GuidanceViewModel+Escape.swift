import HearIAmCore

/// Recovery uses the route-return/obstacle-away bearing with the same pitch-glide vocabulary.
/// The double beep confirms heading only; automatic route re-entry still needs one safe second.
extension GuidanceViewModel {
    static let escapeReasons: [GuidePauseReason]=[.obstacleProximity,.offRoute,.outsideStage]

    func beginEscape(reason: GuidePauseReason, pose: (point: FloorPoint, heading: Double, time: Double), guide: RouteGuide) {
        directionSweep.reset();signals.stopDirection()
        phase = .paused
        escape=EscapeState(reason:reason,startedAt:pose.time,lastSpoken:pose.time)
        message=recoveryInstruction(reason,bearing:guide.recoveryBearing(position:pose.point,headingDegrees:pose.heading))
        voice.play([message])
        tracking.event("escape_start",detail:"reason=\(reason) direction=pitch_sweep")
    }
    func tickEscape(pose: (point: FloorPoint, heading: Double, time: Double), guide: RouteGuide) {
        guard var state=escape else { return }
        let warning=warnings.update(position:pose.point,headingDegrees:pose.heading,obstacles:guide.route.obstacles)
        if warning?.level != signals.warning { signals.setWarning(warning?.level);tracking.event("signal_warning_reason",detail:warning?.detail ?? "off") }
        guard audioIssue == nil else { return }
        if !state.quiet && pose.time-state.startedAt >= EscapeState.quietAfter {
            state.quiet=true;signals.setWarningQuiet(true);tracking.event("escape_quiet")
        }
        if state.quiet && pose.time-state.lastSpoken >= EscapeState.repeatEvery && !speaking {
            state.lastSpoken=pose.time;message=recoveryInstruction(state.reason,bearing:guide.recoveryBearing(position:pose.point,headingDegrees:pose.heading));voice.play([message])
        }
        guard audioIssue == nil else { return }
        if guide.canResume(position:pose.point,trackingValid:true) {
            let since=state.safeSince ?? pose.time
            state.safeSince=since
            if pose.time-since >= EscapeState.safeSeconds { escape=state;endEscape(pose:pose);return }
        } else { state.safeSince=nil }
        guard audioIssue == nil else { return }
        escape=state
        if state.safeSince != nil { suspendDirection();return }
        if let bearing=guide.recoveryBearing(position:pose.point,headingDegrees:pose.heading) {
            updateDirection(bearing:bearing,time:pose.time,context:"recovery reason=\(state.reason)")
        } else { suspendDirection() }
    }
    private func recoveryInstruction(_ reason: GuidePauseReason, bearing: Double?) -> String {
        if reason == .obstacleProximity {
            guard let bearing else { return "멈추세요. 등록한 기물과 가까워졌어요. 이동할 공간을 확인해주세요." }
            let turn=abs(bearing) > 135 ? "뒤로 돌아주세요." : bearing > 10 ? "오른쪽으로 돌아주세요." : bearing < -10 ? "왼쪽으로 돌아주세요." : "몸 방향을 유지해주세요."
            return "멈추세요. 등록한 기물과 가까워졌어요. \(turn) 경고가 끝나면 방향음으로 안내합니다."
        }
        return "멈추세요. 동선에서 벗어났어요. 방향음으로 복귀할 방향을 찾으세요. 삐빅은 방향이 맞았다는 뜻입니다."
    }
    private func endEscape(pose: (point: FloorPoint, heading: Double, time: Double)) {
        guard let state=escape, var guide, guide.resume(position:pose.point,trackingValid:true) else { return }
        self.guide=guide;escape=nil;phase = .guiding
        signals.setWarningQuiet(false);directionSweep.reset();signals.stopDirection();steps.reset()
        voice.play(["다시 안내합니다"])
        tracking.event("escape_end",detail:String(format:"reason=%@ seconds=%.1f quiet=%@","\(state.reason)",pose.time-state.startedAt,state.quiet ? "yes" : "no"))
    }
}
