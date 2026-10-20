import HearIAmCore

/// 안내 중 · 일시정지: signals along the saved route.
/// Direction is the earbud tick of #44: silent while facing the next target within ±n°, ticks that quicken
/// toward it when turned away (left low, right high; no spoken word since 10/20), and one 「삐」 when they
/// stop because the body faces it. Speech otherwise only for steps 1 m ahead and the remaining distance at a few marks (#46).
/// The earbud also gives the obstacle warning and the arrival ding. No vibration (10/20).
extension GuidanceViewModel {
    /// About as long as the ding rings; the distance call-out waits this long after an arrival.
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
        directionTicks.deadbandDegrees=SignalPlayer.directionDeadbandDegrees
        directionTicks.reset();warnings.reset();steps.reset();distances.reset();arrivalShownAt=nil;quietUntil=nil
        signals.setWarning(nil);signals.stopDirection()
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

    /// Ding once; the new target becomes 0° so the direction tick gate immediately guides toward the next spot.
    /// The obstacle warning keeps playing: it used to stop for 1.5 s so the ding was not masked, but a
    /// masked ding is better than a missing warning (10/19). Only the distance call-out waits for the ding.
    private func arrived(_ previous: Int, guide: RouteGuide, time: Double) {
        let name=GuidanceCopy.target(previous,last:guide.route.points.count-1)
        arrivedName=name;arrivalShownAt=time
        directionTicks.reset();quietUntil=time+Self.arrivalQuietSeconds
        signals.stopDirection()
        signals.play(.arrival)
        logSignal("signal_arrival","\(name) next=\(guide.targetIndex)")
    }
    private func signal(pose: (point: FloorPoint, heading: Double, time: Double), guide: RouteGuide) {
        guard guide.route.points.indices.contains(guide.targetIndex) else { return }
        let target=guide.route.points[guide.targetIndex]
        let bearing=StageHeading.bearing(from:pose.point,to:target,headingDegrees:pose.heading)
        let quiet=quietUntil.map { pose.time < $0 } ?? false
        if !quiet { quietUntil=nil }
        // Direction (#44): silent within ±n° of the target; outside it ticks that quicken as the body turns
        // toward it. The tick's pitch gives the side, so 「왼쪽」·「오른쪽」 are not spoken (10/20). The moment
        // the ticks stop because the body faces the target, one 「삐」 (the front beep of #33) says so.
        let wasTicking=directionTicks.activeSide != nil
        if let cue=directionTicks.update(time:pose.time,bearing:bearing) {
            if cue.shouldTick { signals.play(.directionTick(toRight:cue.toRight)) }
        } else if wasTicking {
            if directionTicks.isAligned {
                // Replaces any tick still sounding on the direction node.
                signals.play(.direction(signedDegrees:0))
                logSignal("signal_aligned",String(format:"bearing %+.0f°",bearing))
            } else { signals.stopDirection() }
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
        } else if let mark {
            // Safety signals first: no distance over an obstacle warning, another line or the ding.
            let line=SignalCopy.distance(mark)
            if quiet || signals.warning != nil || speaking {
                logSignal("signal_distance_skipped","\(line) reason=\(quiet ? "arrival" : speaking ? "speaking" : "warning")")
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
