import Foundation
import HearIAmCore

/// ④ Stepped body/head pitch trials, plus the earlier vibration and buzz comparisons.
/// Stepped trials keep the initial direction fixed until the user stops them.
extension SoundTestViewModel {
    static let targets=[90,-90,180,45,-45,135,-135]
    static let foundTolerance=10.0, headTolerance=15.0, headRearm=25.0, steadySeconds=1.0

    var headReceiving: Bool { head.lastSample.map { ProcessInfo.processInfo.systemUptime-$0 < 1 } ?? false }

    func startTrial(_ mode: DirectionTrial.Mode) {
        guard trial == nil else { return }
        guard let bodyStart=body.heading ?? ((mode == .pitchSlider || mode == .pitchReference) ? 0 : nil) else { record("direction_error","몸 방향 값이 없어요. 폰을 허리에 세워 주세요.");return }
        if (mode == .head || mode == .pitchHead) && (!headReceiving || head.heading == nil) { record("direction_error","고개 값이 안 들어와요. 에어팟을 확인해 주세요.");return }
        let target=(mode == .sweep || mode.isStepped) ? 0 : (Self.targets.randomElement() ?? 90)
        detector.reset();sweepGate.reset();stepGate.reset();signals.stopDirection()
        trial=DirectionTrial(mode:mode,target:target,bodyStart:bodyStart,headStart:head.heading,
                             startedAt:ProcessInfo.processInfo.systemUptime)
        record("direction_start","mode=\(mode.rawValue) target=\(target)")
        if mode.isStepped {
            setWarning(nil);signals.stop();haptics.shutdown()
            lastPitchLog=nil;lastReferenceAt=nil;pitchStatus="설명 중"
            let timer=Timer(timeInterval:1.0/30,repeats:true) { [weak self] _ in
                Task { @MainActor in self?.tickStepped() }
            }
            pitchTimer=timer;RunLoop.main.add(timer,forMode:.common)
            speak(mode == .pitchReference ? "기준음 육십 헤르츠를 짧게 반복합니다. 그만을 누르면 끝납니다." :
                mode == .pitchSlider ? "슬라이더를 움직여보세요. 오른쪽은 사십과 오십, 왼쪽은 칠십과 팔십 헤르츠입니다. 영 도에서 잠시 멈추면 기준음과 띠링입니다." :
                "지금 방향이 목표입니다. 오른쪽으로 돌아야 하면 낮은 삐비빅, 왼쪽으로 돌아야 하면 높은 삐비빅입니다. 방향이 맞으면 기준음과 띠링입니다.")
            return
        }
        speak(mode == .sweep ? "지금 몸 방향이 목표입니다. 제자리에서 한 바퀴 돌아보세요. 높아지면 왼쪽, 낮아지면 오른쪽, 방향이 맞으면 삐빅입니다." : "방향을 찾아 주세요")
    }
    func finishTrial(found: Bool) {
        guard let current=trial else { return }
        let now=ProcessInfo.processInfo.systemUptime
        let result=DirectionTrialResult(mode:current.mode,target:current.target,found:found,seconds:now-current.startedAt,
            bodyError:bodyError(current),headError:headError(current),headFoundSeconds:current.headFoundAt.map { $0-current.startedAt })
        trial=nil;pitchTimer?.invalidate();pitchTimer=nil;stepGate.reset()
        stepHertz=nil;pitchStatus="종료";voice.stop()
        results.insert(result,at:0);sweepGate.reset();signals.stopDirection()
        record("direction_result",result.summary)
        if found { signals.play(.arrival) }
    }

    func bodySample(_ heading: Double?) {
        bodyAngle=heading.flatMap { h in trial.map { HeadingMath.wrapDegrees(h-$0.bodyStart) } }
        guard var current=trial, !current.mode.isStepped else { return }
        guard let error=bodyError(current), error.isFinite else {
            if current.mode == .sweep { sweepGate.reset();signals.stopDirection() }
            return
        }
        if current.mode == .sweep {
            guard !speaking, signals.warning == nil else { sweepGate.suspend();signals.stopDirection();return }
            let update=sweepGate.update(time:ProcessInfo.processInfo.systemUptime,bearing:-error)
            if update.stopPrevious { signals.stopDirection() }
            if let sound=update.sound {
                signals.play(sound);record("sweep_trial",String(format:"bearing=%+.1f %@",-error,sound.name))
            }
            return // Keep the target fixed and keep listening until the user ends the trial.
        }
        if let landmark=detector.update(relativeDegrees:error), current.mode == .body || landmark == 0 {
            haptics.play(signedDegrees:landmark)
        }
        let now=ProcessInfo.processInfo.systemUptime
        if abs(error) <= Self.foundTolerance { current.steadySince=current.steadySince ?? now } else { current.steadySince=nil }
        trial=current
        if let since=current.steadySince, now-since >= Self.steadySeconds { finishTrial(found:true) }
    }
    func headSample(_ heading: Double?) {
        headAngle=heading.flatMap { h in trial?.headStart.map { HeadingMath.wrapDegrees(h-$0) } }
        guard var current=trial, current.mode == .head, let error=headError(current) else { return }
        if !current.headLatched && abs(error) <= Self.headTolerance {
            current.headLatched=true
            current.headFoundAt=current.headFoundAt ?? ProcessInfo.processInfo.systemUptime
            signals.play(.buzz(hertz:60,harmonic:true))
        } else if current.headLatched && abs(error) > Self.headRearm { current.headLatched=false }
        trial=current
    }

    /// Angle from the target, 0 when facing it. Positive means the target is to the left.
    private func bodyError(_ trial: DirectionTrial) -> Double? {
        body.heading.map { HeadingMath.wrapDegrees($0-trial.bodyStart-Double(trial.target)) }
    }
    private func headError(_ trial: DirectionTrial) -> Double? {
        guard let start=trial.headStart, let heading=head.heading else { return nil }
        return HeadingMath.wrapDegrees(heading-start-Double(trial.target))
    }
}


extension SoundTestViewModel {
    /// Only five fundamental pitches; every scheduled sound is a finite three-pulse group.
    func tickStepped() {
        guard let trial, trial.mode.isStepped else { return }
        guard !speaking, signals.warning == nil else {
            signals.stopDirection();stepGate.suspend();stepHertz=nil;lastReferenceAt=nil
            pitchStatus=speaking ? "음성 중" : "경고 중";return
        }
        let now=ProcessInfo.processInfo.systemUptime
        if trial.mode == .pitchReference {
            stepHertz=60;pitchStatus="기준음 · 짧게 반복"
            if lastReferenceAt.map({now-$0 >= SteppedDirectionGate.interval}) ?? true {
                if signals.play(.directionBuzz(hertz:60)) { lastReferenceAt=now }
            }
            return
        }
        let bearing: Double?
        if trial.mode == .pitchSlider { bearing=manualBearing }
        else if trial.mode == .pitchHead {
            bearing=head.lastSample.flatMap { now-$0 <= 0.5 ? headError(trial).map { -$0 } : nil }
        } else {
            bearing=body.lastSample.flatMap { now-$0 <= 0.5 ? bodyError(trial).map { -$0 } : nil }
        }
        guard let bearing else {
            signals.stopDirection();stepGate.suspend();stepHertz=nil;pitchStatus="방향 값 대기";return
        }
        let update=stepGate.update(time:now,bearing:bearing)
        stepHertz=stepGate.currentHertz.map(Double.init)
        pitchStatus=stepGate.isAligned ? "정렬 · 기준음과 띠링 후 무음" : abs(bearing) <= SteppedDirectionGate.enterDegrees ? "정렬 확인 중" : bearing < 0 ? "왼쪽으로 맞추기" : "오른쪽으로 맞추기"
        if update.stopPrevious { signals.stopDirection() }
        if let sound=update.sound {
            guard signals.play(sound) else { stepGate.reset();return }
            record(sound == .directionBuzzAligned ? "stepped_aligned" : "stepped_burst",
                   String(format:"mode=%@ bearing=%+.1f hz=%d",trial.mode.rawValue,bearing,stepHertz.map {Int($0)} ?? 0))
        }
        if lastPitchLog.map({now-$0 >= 0.25}) ?? true {
            lastPitchLog=now
            record("stepped_pitch",String(format:"mode=%@ bearing=%+.1f hz=%d aligned=%@",trial.mode.rawValue,bearing,stepGate.currentHertz ?? 0,stepGate.isAligned ? "yes" : "no"))
        }
    }
}
