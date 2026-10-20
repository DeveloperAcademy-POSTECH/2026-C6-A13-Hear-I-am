import Foundation
import HearIAmCore

/// ④ Continuous pitch and counted beep comparisons using body/head direction.
/// Both audio comparisons keep the initial direction fixed until the user stops them.
extension SoundTestViewModel {
    static let targets=[90,-90,180,45,-45,135,-135]
    static let foundTolerance=10.0, headTolerance=15.0, headRearm=25.0, steadySeconds=1.0

    var headReceiving: Bool { head.lastSample.map { ProcessInfo.processInfo.systemUptime-$0 < 1 } ?? false }

    func startTrial(_ mode: DirectionTrial.Mode) {
        guard trial == nil else { return }
        guard let bodyStart=body.heading ?? ((mode == .pitchSlider || mode == .pitchReference || mode == .countSlider) ? 0 : nil) else { record("direction_error","몸 방향 값이 없어요. 폰을 허리에 세워 주세요.");return }
        if (mode == .head || mode == .pitchHead || mode == .countHead) && (!headReceiving || head.heading == nil) { record("direction_error","고개 값이 안 들어와요. 에어팟을 확인해 주세요.");return }
        let target=(mode == .sweep || mode.isTimed) ? 0 : (Self.targets.randomElement() ?? 90)
        detector.reset();sweepGate.reset();pitchGate.reset();countGate.reset();signals.stopDirection()
        trial=DirectionTrial(mode:mode,target:target,bodyStart:bodyStart,headStart:head.heading,
                             startedAt:ProcessInfo.processInfo.systemUptime)
        record("direction_start","mode=\(mode.rawValue) target=\(target)")
        if mode.isCounted {
            setWarning(nil);signals.stop();haptics.shutdown();continuous.stop()
            countStatus="설명 중"
            let timer=Timer(timeInterval:1.0/30,repeats:true) { [weak self] _ in
                Task { @MainActor in self?.tickCounted() }
            }
            pitchTimer=timer;RunLoop.main.add(timer,forMode:.common)
            speak(mode == .countSlider ?
                "슬라이더를 움직여보세요. 왼쪽은 높은 음, 오른쪽은 낮은 음입니다. 가까워질수록 세 번, 두 번, 한 번. 맞으면 띠링 후 조용해집니다." :
                "지금 방향이 목표입니다. 왼쪽으로 돌아야 하면 높은 음, 오른쪽이면 낮은 음입니다. 가까워질수록 세 번, 두 번, 한 번. 맞으면 띠링 후 조용해집니다.")
            return
        }
        if mode.isContinuous {
            setWarning(nil);signals.stop();haptics.shutdown()
            guard continuous.start() else { trial=nil;return }
            lastPitchLog=nil;pitchStatus="설명 중"
            let timer=Timer(timeInterval:1.0/30,repeats:true) { [weak self] _ in
                Task { @MainActor in self?.tickContinuous() }
            }
            pitchTimer=timer;RunLoop.main.add(timer,forMode:.common)
            speak(mode == .pitchReference ? "작은 기준음 육십 헤르츠가 끊기지 않고 이어집니다. 그만을 누르면 끝납니다." :
                mode == .pitchSlider ? "슬라이더를 움직여보세요. 왼쪽 보정은 팔십에서 육십으로, 오른쪽 보정은 사십에서 육십으로 소리가 이어집니다. 방향이 맞으면 띠링입니다." :
                "지금 방향이 목표입니다. 작은 소리가 계속 이어집니다. 방향을 맞출수록 소리가 육십 헤르츠에 가까워지고, 맞으면 띠링입니다.")
            return
        }
        speak(mode == .sweep ? "지금 몸 방향이 목표입니다. 제자리에서 한 바퀴 돌아보세요. 높아지면 왼쪽, 낮아지면 오른쪽, 방향이 맞으면 삐빅입니다." : "방향을 찾아 주세요")
    }
    func finishTrial(found: Bool) {
        guard let current=trial else { return }
        let now=ProcessInfo.processInfo.systemUptime
        let result=DirectionTrialResult(mode:current.mode,target:current.target,found:found,seconds:now-current.startedAt,
            bodyError:bodyError(current),headError:headError(current),headFoundSeconds:current.headFoundAt.map { $0-current.startedAt })
        trial=nil;pitchTimer?.invalidate();pitchTimer=nil;continuous.stop();pitchGate.reset();countGate.reset();countStatus="종료"
        pitchHertz=nil;pitchStatus="종료";voice.stop()
        results.insert(result,at:0);sweepGate.reset();signals.stopDirection()
        record("direction_result",result.summary)
        if found { signals.play(.countDirectionAligned) }
    }

    func bodySample(_ heading: Double?) {
        bodyAngle=heading.flatMap { h in trial.map { HeadingMath.wrapDegrees(h-$0.bodyStart) } }
        guard var current=trial, !current.mode.isTimed else { return }
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
    /// Feed one oscillator. No cadence, buzz buffer or periodic note restart is used here.
    func tickContinuous() {
        guard let trial, trial.mode.isContinuous else { return }
        guard !speaking, signals.warning == nil else {
            continuous.setHertz(nil);pitchGate.suspend();pitchHertz=nil
            pitchStatus=speaking ? "음성 중" : "경고 중";return
        }
        let now=ProcessInfo.processInfo.systemUptime
        if trial.mode == .pitchReference {
            continuous.setHertz(60,volume:pitchVolume);pitchHertz=60;pitchStatus="기준음 · 계속 이어짐";return
        }
        let bearing: Double?
        if trial.mode == .pitchSlider { bearing=manualBearing }
        else if trial.mode == .pitchHead {
            bearing=head.lastSample.flatMap {now-$0 <= 0.5 ? headError(trial).map {-$0} : nil}
        } else {
            bearing=body.lastSample.flatMap {now-$0 <= 0.5 ? bodyError(trial).map {-$0} : nil}
        }
        guard let bearing else {
            continuous.setHertz(nil);pitchGate.suspend();pitchHertz=nil;pitchStatus="방향 값 대기";return
        }
        pitchGate.resolution=pitchResolution
        let update=pitchGate.update(time:now,bearing:bearing)
        continuous.setHertz(update.hertz,volume:pitchVolume);pitchHertz=update.hertz
        pitchStatus=pitchGate.isAligned ? "정렬 · 60Hz 유지" : abs(bearing) <= ContinuousDirectionGate.enterDegrees ? "정렬 확인 중" : bearing < 0 ? "왼쪽으로 맞추기" : "오른쪽으로 맞추기"
        if update.aligned {
            signals.play(.countDirectionAligned);record("continuous_aligned",String(format:"mode=%@ bearing=%+.1f",trial.mode.rawValue,bearing))
        }
        if lastPitchLog.map({now-$0 >= 0.25}) ?? true {
            lastPitchLog=now
            record("continuous_pitch",String(format:"mode=%@ bearing=%+.1f hz=%.2f volume=%.2f resolution=%@ aligned=%@",trial.mode.rawValue,bearing,update.hertz ?? 0,pitchVolume,pitchResolution.rawValue,pitchGate.isAligned ? "yes" : "no"))
        }
    }
}


extension SoundTestViewModel {
    /// Poll the current bearing only; the gate emits whole groups at a fixed cadence.
    func tickCounted() {
        guard let trial, trial.mode.isCounted else { return }
        guard !speaking, signals.warning == nil else {
            signals.stopDirection();countGate.suspend()
            countStatus=speaking ? "음성 중" : "경고 중";return
        }
        let now=ProcessInfo.processInfo.systemUptime
        let bearing: Double?
        if trial.mode == .countSlider { bearing=manualBearing }
        else if trial.mode == .countHead {
            bearing=head.lastSample.flatMap { now-$0 <= 0.5 ? headError(trial).map {-$0} : nil }
        } else {
            bearing=body.lastSample.flatMap { now-$0 <= 0.5 ? bodyError(trial).map {-$0} : nil }
        }
        guard let bearing else {
            signals.stopDirection();countGate.suspend();countStatus="방향 값 대기";return
        }
        let update=countGate.update(time:now,bearing:bearing)
        if update.stopPrevious { signals.stopDirection() }
        if let sound=update.sound {
            guard signals.play(sound) else { return }
            record("count_direction",String(format:"mode=%@ bearing=%+.1f sound=%@",trial.mode.rawValue,bearing,sound.name))
        }
        countStatus=countGate.isAligned ? "정렬 · 띠링 후 무음" :
            abs(bearing) <= CountedDirectionGate.enterDegrees ? "정렬 확인 중" :
            "\(countGate.toRight == true ? "오른쪽 · 낮은 음" : "왼쪽 · 높은 음") · \(countGate.count ?? 1)번"
    }
}
