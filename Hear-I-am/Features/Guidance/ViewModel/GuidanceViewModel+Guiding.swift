import HearIAmCore

/// 안내 중 · 일시정지: signals along the saved route, decided 10/17 (comparison option ②).
/// Direction is the waist vibration (next target = 0°, every 45°). Speech only when needed:
/// corrections past 45° for 1 s, steps 1 m ahead. The earbud gives the obstacle warning and the arrival ding.
/// Walking on track is silent.
extension GuidanceViewModel {
    static let arrivalShownSeconds=2.0

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
        landmarks.reset();warnings.reset();corrections.reset();steps.reset();arrivalShownAt=nil
        signals.setWarning(nil)
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

    /// Ding once; the new target becomes 0° so the next vibration points the way. No speech.
    private func arrived(_ previous: Int, guide: RouteGuide, time: Double) {
        let name=GuidanceCopy.target(previous,last:guide.route.points.count-1)
        arrivedName=name;arrivalShownAt=time
        landmarks.reset();corrections.reset()
        signals.play(.arrival)
        tracking.event("signal_arrival",detail:"\(name) next=\(guide.targetIndex)")
    }
    private func signal(pose: (point: FloorPoint, heading: Double, time: Double), guide: RouteGuide) {
        guard guide.route.points.indices.contains(guide.targetIndex) else { return }
        let target=guide.route.points[guide.targetIndex]
        let bearing=StageHeading.bearing(from:pose.point,to:target,headingDegrees:pose.heading)
        // The detector takes the body relative to the target, the opposite sign of the bearing.
        if let landmark=landmarks.update(relativeDegrees:-bearing) { haptics.play(signedDegrees:landmark) }
        let warning=warnings.update(position:pose.point,headingDegrees:pose.heading,obstacles:guide.route.obstacles)
        if warning?.level != signals.warning {
            signals.setWarning(warning?.level)
            tracking.event("signal_warning_reason",detail:warning?.detail ?? "off")
        }
        if let step=steps.update(position:pose.point,target:target,obstacles:guide.route.obstacles) {
            voice.play([step.line]);tracking.event("signal_step",detail:step.detail)
        } else if let correction=corrections.update(time:pose.time,bearing:bearing) {
            voice.direction(correction.line)
            tracking.event("signal_correction",detail:String(format:"%@ bearing %+.0f°",correction.rawValue,bearing))
        }
    }
    private func paused(guide: RouteGuide) {
        phase = .paused
        switch guide.pauseReason {
        case .obstacleProximity: message="등록한 기물과 가까워졌어요. 현재 위치와 동선을 확인해주세요."
        case .offRoute,.outsideStage: message="저장된 동선의 안내 범위를 벗어났어요. 현재 위치와 동선을 확인해주세요."
        default: message="위치와 방향을 다시 확인해주세요."
        }
        read(["잠시 멈춰주세요. \(message)"])
    }
}
