import HearIAmCore

/// 안내 중 · 일시정지: signals along the saved route.
/// Direction is the earbud tick of #44: silent while facing the next target within ±n°, 「왼쪽」 or 「오른쪽」 once
/// when turned away, then ticks that quicken toward it (left low, right high), and a soft rising chime when they
/// stop because the body faces it. The side of the next point is also said once after the start announcement,
/// and at each point once the ding has rung (10/21: said over the ding it was not heard). When that point stands on
/// a chair or stairs, where it lies is said instead (「오른쪽에 의자」, #72). Speech otherwise only for the remaining
/// distance at a few marks (#46). The earbud also gives the obstacle warning and the arrival ding. No vibration (10/20).
/// Chairs and stairs are not obstacles: no warning, no stop, no stepping aside (#72).
extension GuidanceViewModel {
    /// About as long as the ding rings; the distance call-out waits this long after an arrival.
    static let arrivalShownSeconds=2.0, arrivalQuietSeconds=0.7, alignedQuietSeconds=0.35

    var canResume: Bool {
        guard let pose=freshPose(), let guide else { return false }
        if guide.rehearsalReturnArrivalIndex != nil {return guide.canResumeForwardAfterRehearsalReturn(position:pose.point,trackingValid:true)}
        return guide.canResume(position:pose.point,trackingValid:true)
    }
    func pause() {
        guard phase == .guiding || phase == .starting || phase == .approaching else { return }
        invalidateTasks();guide?.pause();phase = started ? .paused : .departure
        message="현재 목표는 \(targetName)이에요."
        read([voiceShouldListen ? VoiceStepCopy.paused : "안내를 일시정지했습니다. 다시 시작 버튼을 누르면 이어서 안내합니다."])
    }
    /// Clears every signal rule; called when guidance starts or resumes.
    func resetSignals() {
        directionTicks.deadbandDegrees=SignalPlayer.directionDeadbandDegrees
        directionTicks.reset();warnings.reset();distances.reset();arrivalShownAt=nil;quietUntil=nil;aligningStep=nil;announceNextSide=false;announceStepHint=false;pendingTurnSide=false;ticksWaitForWord=false
        signals.setWarning(nil);signals.stopDirection()
    }
    func tickGuiding(pose: (point: FloorPoint, heading: Double, time: Double), guide current: RouteGuide) {
        var guide=current
        let previous=guide.targetIndex
        let wasHolding=guide.isHolding
        let previousFacing=guide.facingPointIndex
        let update=guide.observe(time:pose.time,position:pose.point,headingDegrees:pose.heading,trackingValid:true,allowsTargetAdvance:aligningStep == nil,allowsFacingCompletion:!speaking && audioIssue == nil)
        self.guide=guide;performanceHoldRemaining=guide.holdRemaining;cue=guide.cue(position:pose.point,headingDegrees:pose.heading)
        tracking.setGuidanceTarget(guide.facingPointIndex ?? guide.targetIndex,completed:guide.state == .completed)
        if let index=guide.rehearsalReturnArrivalIndex {reachedVoiceReturn(index,time:pose.time);return}
        if let previousFacing, guide.facingPointIndex == nil, update.state != .paused {
            signals.playAligned();directionTicks.reset();distances.reset()
            announceNextSide=true;pendingTurnSide=false;ticksWaitForWord=false
            announceStepHint=guide.route.step(at:guide.targetIndex) != nil
            quietUntil=pose.time+Self.arrivalQuietSeconds
            logSignal("point_facing_aligned","point=\(previousFacing)")
        }
        if update.state == .completed { playCompletion();return }
        if update.state == .paused {
            paused(guide:guide)
            return
        }
        if let facing=guide.facingPointIndex, facing != previousFacing {
            captureReplay(force:true);arrived(facing,guide:guide,time:pose.time)
        } else if update.targetIndex != previous { captureReplay(force:true);arrived(previous,guide:guide,time:pose.time) }
        guard phase == .guiding else { return }
        if let shown=arrivalShownAt, pose.time-shown > Self.arrivalShownSeconds { arrivedName=nil;arrivalShownAt=nil }
        if guide.isHolding {
            // The reached step's facing instruction is separate from the muted next-leg guidance.
            signal(pose:pose,guide:guide)
            return
        }
        if wasHolding && aligningStep == nil {
            directionTicks.reset();distances.reset();announceNextSide=true;pendingTurnSide=false
        }
        if wasHolding { logSignal("performance_hold_end","next=\(guide.targetIndex)") }
        signal(pose:pose,guide:guide)
    }

    /// Speaks the reached point name (「피원」 · 「의자일」 · 「계단일」, #74, #76, #88) instead of the arrival ding.
    /// If the reached point stands on a chair or stairs with a `facingEdge`, aligns the performer with
    /// that edge first (#76); once aligned, the side of the next target spot is announced.
    private func arrived(_ previous: Int, guide: RouteGuide, time: Double) {
        let name=guide.route.spokenPointName(at:previous)
        let label=guide.route.pointLabel(at:previous)
        arrivedName=label;arrivalShownAt=time
        directionTicks.reset();announceNextSide=true;pendingTurnSide=false
        if guide.route.facing(at:previous) != nil {
            aligningStep=nil;announceStepHint=false
        } else if let step=guide.route.step(at:previous), step.facingEdge != nil {
            aligningStep=step
            announceStepHint=false
        } else {
            aligningStep=nil
            announceStepHint=guide.route.step(at:guide.targetIndex) != nil
        }
        signals.stopDirection()
        let facingLine=guide.route.facing(at:previous).map { "그 자리에서 \($0.label) 방향을 바라봐주세요." }
        ticksWaitForWord=voice.play([previous == guide.route.points.count-1 ? "도착점에 도착했습니다." : name] + (facingLine.map {[$0]} ?? []))
        quietUntil=ticksWaitForWord ? nil : time+Self.arrivalQuietSeconds
        logSignal("signal_arrival","\(label)(\(name)) next=\(guide.targetIndex)\(aligningStep.map { " align=\($0.name)#\(($0.facingEdge ?? 0)+1)" } ?? "")")
        if guide.isHolding { logSignal("performance_hold_start","point=\(previous) seconds=\(guide.holdRemaining)") }
    }
    func signal(pose: (point: FloorPoint, heading: Double, time: Double), guide: RouteGuide) {
        directionTicks.deadbandDegrees=SignalPlayer.directionDeadbandDegrees
        directionTicks.releaseMarginDegrees=3
        var quiet=quietUntil.map { pose.time < $0 } ?? false
        if !quiet { quietUntil=nil }
        if ticksWaitForWord, !speaking { ticksWaitForWord=false }
        if let index=guide.facingPointIndex, let facing=guide.route.facing(at:index) {
            directionTicks.deadbandDegrees=RouteGuide.facingToleranceDegrees
            directionTicks.releaseMarginDegrees=0
            signalStepAlignment(pose:pose,step:nil,bearing:facing.bearing(headingDegrees:pose.heading),quiet:quiet,guide:guide)
            return
        }
        if let step=aligningStep, let stepBearing=step.facingBearing(headingDegrees:pose.heading) {
            signalStepAlignment(pose:pose,step:step,bearing:stepBearing,quiet:quiet,guide:guide)
            return
        }
        aligningStep=nil
        guard !guide.isHolding, guide.route.points.indices.contains(guide.targetIndex) else { return }
        let target=guide.route.points[guide.targetIndex]
        let distance=pose.point.distance(to:target)
        let inArrivalZone=distance <= guide.settings.arrivalRadius
        let bearing=StageHeading.bearing(from:pose.point,to:target,headingDegrees:pose.heading)
        // Direction (#44): silent within ±n° of the target; outside it 「왼쪽」 or 「오른쪽」 once, then ticks that
        // quicken as the body turns toward it. The moment the ticks stop because the body faces the target,
        // the aligned chime says so. Chairs and stairs use the exact same direction guidance (#76).
        // Once inside `arrivalRadius` (waiting for the 0.8s arrival dwell, #88), do not start a new direction
        // correction for the point being stepped on so it never gets cut off by the imminent arrival speech.
        let wasTicking=directionTicks.activeSide != nil
        let cue: DirectionTickGate.Cue?
        if inArrivalZone && !announceNextSide {
            directionTicks.reset()
            pendingTurnSide=false
            if wasTicking { signals.stopDirection() }
            cue=nil
        } else {
            cue=directionTicks.update(time:pose.time,bearing:bearing)
        }
        // The side waits for the point announcement and for any line being spoken; facing the target already needs no word.
        if announceNextSide, !quiet, !speaking {
            announceNextSide=false
            if let cue {
                sayDirection(cue.word,volume:SignalVolume.nextSide,bearing:bearing,guide:guide)
            }
        } else if !announceNextSide, !inArrivalZone, let cue, cue.spokenWord != nil || pendingTurnSide {
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
        } else if wasTicking, !inArrivalZone {
            if directionTicks.isAligned {
                // Replaces any tick still sounding on the direction node.
                signals.playAligned()
                logSignal("signal_aligned",String(format:"bearing %+.0f°",bearing))
                if announceStepHint { quietUntil=pose.time+Self.alignedQuietSeconds;quiet=true }
            } else { signals.stopDirection() }
        }
        // Once aligned toward a chair or stairs, briefly announce 「의자」 or 「계단」 once before distance marks (#76).
        if cue == nil, !announceNextSide, announceStepHint, !quiet, !speaking {
            announceStepHint=false
            if let step=guide.route.step(at:guide.targetIndex) {
                let line=SignalCopy.stepHint(stairs:step.kind == .stairs)
                ticksWaitForWord=voice.play([line])
                logSignal(ticksWaitForWord ? "signal_step_hint" : "signal_step_hint_skipped",
                          String(format:"%@ %@ bearing %+.0f° target=%d",line,step.name,bearing,guide.targetIndex))
            }
        }
        // Distance marks wait until any step hint for this leg has been announced.
        guard !announceStepHint else { return }
        let mark=distances.update(position:pose.point,target:target)
        if let mark {
            let line=SignalCopy.distance(mark)
            if quiet || speaking {
                logSignal("signal_distance_skipped","\(line) reason=\(quiet ? "arrival" : "speaking")")
            } else { voice.direction(line);logSignal("signal_distance",line) }
        }
    }
    /// 1st orientation after arriving on a chair or stairs (#76): guides the performer's heading toward
    /// the green `facingEdge` outward normal, plays the aligned chime when aligned, and then resumes
    /// route guidance toward the next spot.
    private func signalStepAlignment(pose: (point: FloorPoint, heading: Double, time: Double), step: StageObstacle?, bearing: Double, quiet: Bool, guide: RouteGuide) {
        if announceNextSide && (quiet || speaking) { return }
        let cue=directionTicks.update(time:pose.time,bearing:bearing)
        if let cue {
            let lookWord=SignalCopy.look(toRight:cue.toRight)
            if announceNextSide {
                announceNextSide=false
                sayDirection(lookWord,volume:SignalVolume.nextSide,bearing:bearing,guide:guide)
            } else if cue.spokenWord != nil || pendingTurnSide {
                if speaking, !voice.speakingDirection {
                    if !pendingTurnSide { logSignal("signal_direction_word_deferred",String(format:"%@ bearing %+.0f° reason=speaking",lookWord,bearing)) }
                    pendingTurnSide=true
                } else {
                    pendingTurnSide=false
                    if speaking { logSignal("signal_voice_cut","\(spokenText) for=\(lookWord)") }
                    sayDirection(lookWord,volume:SignalVolume.speech,bearing:bearing,guide:guide,interrupting:true)
                }
            }
            if cue.shouldTick, !announceNextSide, !pendingTurnSide, !ticksWaitForWord {
                signals.play(.directionTick(toRight:cue.toRight))
            }
        } else if !quiet, !speaking {
            // Explicit facings finish only after the core's fresh one-second alignment dwell.
            guard let step else { signals.stopDirection();return }
            signals.playAligned()
            logSignal("signal_step_aligned",String(format:"%@ edge=%d bearing %+.0f°",step.name,(step.facingEdge ?? 0)+1,bearing))
            aligningStep=nil
            directionTicks.reset();distances.reset()
            announceNextSide=true;announceStepHint=guide.route.step(at:guide.targetIndex) != nil
            pendingTurnSide=false;ticksWaitForWord=false
            quietUntil=pose.time+Self.arrivalQuietSeconds
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
        read([voiceShouldListen ? VoiceStepCopy.autoPaused(message) : "잠시 멈춰주세요. \(message)"])
    }
}
