import HearIAmCore

/// 빠져나오기: instead of waiting for a button, say which way to step aside and resume by itself after
/// one safe second. No direction tick or vibration meanwhile (10/20); the line says the way. After 10 s the warning softens
/// and only the line repeats every 5 s.
extension GuidanceViewModel {
    static let escapeReasons: [GuidePauseReason]=[.obstacleProximity,.offRoute,.outsideStage]

    func beginEscape(reason: GuidePauseReason, pose: (point: FloorPoint, heading: Double, time: Double), guide: RouteGuide) {
        phase = .paused
        let bearing=escapeBearing(pose:pose,guide:guide)
        escape=EscapeState(reason:reason,startedAt:pose.time,lastSpoken:pose.time)
        message=SignalCopy.escape(bearing:bearing)
        voice.play([message])
        let side=abs(bearing) > 135 ? "back" : bearing > 0 ? "right" : "left"
        logSignal("escape_start",String(format:"reason=%@ side=%@ bearing=%+.0f°","\(reason)",side,bearing))
    }
    func tickEscape(pose: (point: FloorPoint, heading: Double, time: Double), guide: RouteGuide) {
        guard var state=escape else { return }
        let bearing=escapeBearing(pose:pose,guide:guide)
        let warning=warnings.update(position:pose.point,headingDegrees:pose.heading,obstacles:guide.route.obstacles)
        if warning?.level != signals.warning { signals.setWarning(warning?.level);logSignal("signal_warning_reason",warning?.detail ?? "off") }
        if !state.quiet && pose.time-state.startedAt >= EscapeState.quietAfter {
            state.quiet=true;signals.setWarningQuiet(true);tracking.event("escape_quiet")
        }
        if state.quiet && pose.time-state.lastSpoken >= EscapeState.repeatEvery && !speaking {
            state.lastSpoken=pose.time;message=SignalCopy.escape(bearing:bearing);voice.play([message])
        }
        if guide.canResume(position:pose.point,trackingValid:true) {
            let since=state.safeSince ?? pose.time
            state.safeSince=since
            if pose.time-since >= EscapeState.safeSeconds { escape=state;endEscape(pose:pose);return }
        } else { state.safeSince=nil }
        escape=state
    }
    /// Steps aside toward the route: the closest point of the current segment, or, when already on it,
    /// away from the nearest blocking obstacle. Positive bearing means to the right.
    private func escapeBearing(pose: (point: FloorPoint, heading: Double, time: Double), guide: RouteGuide) -> Double {
        let points=guide.route.points, i=guide.targetIndex
        if i > 0, points.indices.contains(i) {
            let toward=Self.closest(on:points[i-1],points[i],to:pose.point)
            if pose.point.distance(to:toward) > 0.1 { return StageHeading.bearing(from:pose.point,to:toward,headingDegrees:pose.heading) }
        }
        guard let obstacle=guide.route.obstacles.filter(\.blocksPath).min(by: { $0.distance(to:pose.point) < $1.distance(to:pose.point) }) else { return 0 }
        return HeadingMath.wrapDegrees(StageHeading.bearing(from:pose.point,to:obstacle.closestPoint(to:pose.point),headingDegrees:pose.heading)+180)
    }
    private func endEscape(pose: (point: FloorPoint, heading: Double, time: Double)) {
        guard let state=escape, var guide, guide.resume(position:pose.point,trackingValid:true) else { return }
        self.guide=guide;escape=nil;phase = .guiding
        signals.setWarningQuiet(false);directionTicks.reset();steps.reset();distances.reset()
        voice.play(["다시 안내합니다"])
        logSignal("escape_end",String(format:"reason=%@ seconds=%.1f quiet=%@","\(state.reason)",pose.time-state.startedAt,state.quiet ? "yes" : "no"))
    }
    private static func closest(on a: FloorPoint, _ b: FloorPoint, to p: FloorPoint) -> FloorPoint {
        let dx=b.x-a.x, dy=b.y-a.y, n=dx*dx+dy*dy
        let t=n > 0 ? max(0,min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/n)) : 0
        return FloorPoint(a.x+t*dx,a.y+t*dy)
    }
}
