import HearIAmCore

/// 안내 중 · 일시정지: signals along the saved route.
/// Direction is the earbud tick of #44: silent while facing the next target within ±n°, 「왼쪽」 or 「오른쪽」 once
/// when turned away, then ticks that quicken toward it (left low, right high), and a soft rising chime when they
/// stop because the body faces it. The side of the next point is also said once after the start announcement,
/// and at each point once the ding has rung (10/21: said over the ding it was not heard). Speech otherwise only for steps 1 m ahead and the remaining distance at a few marks (#46).
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
        directionTicks.reset();warnings.reset();steps.reset();distances.reset();arrivalShownAt=nil;quietUntil=nil;announceNextSide=false;pendingTurnSide=false;ticksWaitForWord=false
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
    /// Once the ding has rung the side of that spot is said (10/21: dropped with the other words on 10/20 by mistake).
    /// The obstacle warning keeps playing: it used to stop for 1.5 s so the ding was not masked, but a
    /// masked ding is better than a missing warning (10/19). Only the distance call-out waits for the ding.
    private func arrived(_ previous: Int, guide: RouteGuide, time: Double) {
        let name=GuidanceCopy.target(previous,last:guide.route.points.count-1)
        arrivedName=name;arrivalShownAt=time
        directionTicks.reset();quietUntil=time+Self.arrivalQuietSeconds;announceNextSide=true;pendingTurnSide=false
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
        // Direction (#44): silent within ±n° of the target; outside it 「왼쪽」 or 「오른쪽」 once, then ticks that
        // quicken as the body turns toward it. The word was dropped on 10/20 and restored on 10/21. The moment
        // the ticks stop because the body faces the target, the aligned chime says so.
        let wasTicking=directionTicks.activeSide != nil
        let cue=directionTicks.update(time:pose.time,bearing:bearing)
        // The side waits for the ding and for any line being spoken; facing the target already needs no word.
        if ticksWaitForWord, !speaking { ticksWaitForWord=false }
        if announceNextSide, !quiet {
            if let cue, !speaking {
                announceNextSide=false
                sayDirection(cue.word,volume:SignalVolume.nextSide,bearing:bearing,guide:guide)
            } else if cue == nil { announceNextSide=false }
        } else if !announceNextSide, let cue, cue.spokenWord != nil || pendingTurnSide {
            // Turned away from the target, or over to its other side. Not while the next side waits to be said.
            // A line still being spoken used to drop the word, and it comes only once (#57: lost twice after
            // 「1미터」·「50센티」). A distance or an earlier side is cut for it; an instruction or a step is not,
            // so the word waits for it and then names the side the target is on by then.
            if speaking, !voice.speakingDirection {
                if !pendingTurnSide { logSignal("signal_direction_word_deferred",String(format:"%@ bearing %+.0f° reason=speaking",cue.word,bearing)) }
                pendingTurnSide=true
            } else {
                pendingTurnSide=false
                if speaking { logSignal("signal_voice_cut","\(spokenText) for=\(cue.word)") }
                sayDirection(cue.word,volume:SignalVolume.speech,bearing:bearing,guide:guide,interrupting:true)
            }
        }
        // Facing the target before the word could be said: nothing to say.
        if cue == nil { pendingTurnSide=false }
        if let cue {
            // The word comes first: no tick until the side waiting to be said, or being said, is done.
            if cue.shouldTick, !announceNextSide, !pendingTurnSide, !ticksWaitForWord { signals.play(.directionTick(toRight:cue.toRight)) }
        } else if wasTicking {
            if directionTicks.isAligned {
                // Replaces any tick still sounding on the direction node.
                signals.play(.aligned)
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
    /// Speaks a side and holds the ticks until it is done; logs whether it was actually said.
    private func sayDirection(_ word: String, volume: Float, bearing: Double, guide: RouteGuide, interrupting: Bool = false) {
        ticksWaitForWord=voice.direction(word,volume:volume,interrupting:interrupting)
        let detail=String(format:"%@ bearing %+.0f° target=%d",word,bearing,guide.targetIndex)
        if ticksWaitForWord { logSignal("signal_direction_word",detail) } else { logSignal("signal_direction_word_skipped",detail) }
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
