import HearIAmCore

/// 안내 중 · 일시정지: signals along the saved route, decided 10/17 (comparison option ②).
/// Direction is the waist vibration (next target = 0°, every 45°), with the earbud direction beep at
/// the same moment unless the sound test tab chose only one of them (#33). Speech only when needed:
/// corrections past 45° for 1 s, steps 1 m ahead, the remaining distance at a few marks (10/19).
/// The earbud gives the obstacle warning and the arrival ding.
/// Walking on track is silent.
extension GuidanceViewModel {
    /// About as long as the ding rings. On 10/19 a point brought up to seven sounds within 3 s; 1.5 s of
    /// silence was considered, but at 0.5 m/s it lets the performer walk 0.75 m on without a new direction.
    static let arrivalShownSeconds=2.0, arrivalQuietSeconds=0.7

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
        landmarks.reset();warnings.reset();corrections.reset();steps.reset();distances.reset();arrivalShownAt=nil;quietUntil=nil
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

    /// Ding once, then one direction signal for the new target once it has rung. No speech.
    /// The obstacle warning keeps playing: it used to stop for 1.5 s so the ding was not masked, but a
    /// masked ding is better than a missing warning (10/19).
    private func arrived(_ previous: Int, guide: RouteGuide, time: Double) {
        let name=GuidanceCopy.target(previous,last:guide.route.points.count-1)
        arrivedName=name;arrivalShownAt=time
        landmarks.reset();corrections.reset();quietUntil=time+Self.arrivalQuietSeconds
        signals.play(.arrival)
        logSignal("signal_arrival","\(name) next=\(guide.targetIndex)")
    }
    private func signal(pose: (point: FloorPoint, heading: Double, time: Double), guide: RouteGuide) {
        guard guide.route.points.indices.contains(guide.targetIndex) else { return }
        let target=guide.route.points[guide.targetIndex]
        let bearing=StageHeading.bearing(from:pose.point,to:target,headingDegrees:pose.heading)
        let quiet=quietUntil.map { pose.time < $0 } ?? false
        // The detector takes the body relative to the target, the opposite sign of the bearing.
        if !quiet, quietUntil != nil {
            quietUntil=nil
            let landmark=DirectionPattern.nearest(-bearing)
            haptics.playDirection(signedDegrees:landmark,signals:signals)
            // Seed the detector so the same landmark does not fire again on the next tick.
            landmarks.reset();_=landmarks.update(relativeDegrees:-bearing)
        } else if !quiet, let landmark=landmarks.update(relativeDegrees:-bearing) {
            haptics.playDirection(signedDegrees:landmark,signals:signals)
        }
        let warning=warnings.update(position:pose.point,headingDegrees:pose.heading,obstacles:guide.route.obstacles)
        if warning?.level != signals.warning {
            signals.setWarning(warning?.level)
            logSignal("signal_warning_reason",warning?.detail ?? "off")
        }
        // Every tick, so a mark passed while something else speaks is dropped rather than said late.
        let mark=distances.update(position:pose.point,target:target)
        if let step=steps.update(position:pose.point,target:target,obstacles:guide.route.obstacles) {
            voice.play([step.line]);logSignal("signal_step",step.detail)
            if let mark { logSignal("signal_distance_skipped","\(SignalCopy.distance(mark)) reason=step") }
        } else if quiet {
            if let mark { logSignal("signal_distance_skipped","\(SignalCopy.distance(mark)) reason=arrival") }
        } else if let correction=corrections.update(time:pose.time,bearing:bearing) {
            voice.direction(correction.line)
            logSignal("signal_correction",String(format:"%@ bearing %+.0f°",correction.rawValue,bearing))
            if let mark { logSignal("signal_distance_skipped","\(SignalCopy.distance(mark)) reason=correction") }
        } else if let mark {
            // Safety signals first: no distance over an obstacle warning or another line.
            let line=SignalCopy.distance(mark)
            if signals.warning != nil || speaking {
                logSignal("signal_distance_skipped","\(line) reason=\(speaking ? "speaking" : "warning")")
            } else { voice.direction(line);logSignal("signal_distance",line) }
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
