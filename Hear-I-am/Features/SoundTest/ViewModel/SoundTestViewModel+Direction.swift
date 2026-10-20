import Foundation
import HearIAmCore

/// ③ Find a target direction by the direction ticks of guidance or by head (earbud buzz).
/// The trial ends after facing the target with the body for one second.
extension SoundTestViewModel {
    static let targets=[90,-90,180,45,-45,135,-135]
    static let foundTolerance=10.0, headTolerance=15.0, headRearm=25.0, steadySeconds=1.0

    var headReceiving: Bool { head.lastSample.map { ProcessInfo.processInfo.systemUptime-$0 < 1 } ?? false }

    func startTrial(_ mode: DirectionTrial.Mode) {
        guard trial == nil else { return }
        guard let bodyStart=body.heading else { record("direction_error","몸 방향 값이 없어요. 폰을 허리에 세워 주세요.");return }
        if mode == .head && !headReceiving { record("direction_error","고개 값이 안 들어와요. 에어팟을 확인해 주세요.");return }
        let target=Self.targets.randomElement() ?? 90
        directionTicks.deadbandDegrees=deadbandDegrees
        directionTicks.reset()
        trial=DirectionTrial(mode:mode,target:target,bodyStart:bodyStart,headStart:head.heading,
                             startedAt:ProcessInfo.processInfo.systemUptime)
        record("direction_start","mode=\(mode.rawValue) target=\(target) deadband=\(Int(deadbandDegrees))")
        if mode != .tick { speak("방향을 찾아 주세요") }
    }
    func finishTrial(found: Bool) {
        guard let current=trial else { return }
        let now=ProcessInfo.processInfo.systemUptime
        let result=DirectionTrialResult(mode:current.mode,target:current.target,found:found,seconds:now-current.startedAt,
            bodyError:bodyError(current),headError:headError(current),headFoundSeconds:current.headFoundAt.map { $0-current.startedAt })
        trial=nil;results.insert(result,at:0)
        signals.stopDirection()
        record("direction_result",result.summary)
        if found { signals.play(.arrival) }
    }

    func bodySample(_ heading: Double?) {
        bodyAngle=heading.flatMap { h in trial.map { HeadingMath.wrapDegrees(h-$0.bodyStart) } }
        guard var current=trial, let error=bodyError(current) else { return }
        let now=ProcessInfo.processInfo.systemUptime
        let tolerance: Double
        if current.mode == .tick {
            tolerance=deadbandDegrees
            // As in guidance: one 「삐」 the moment the ticks stop on facing the target.
            let wasTicking=directionTicks.activeSide != nil
            if let cue=directionTicks.update(time:now,bearing:-error) {
                if cue.shouldTick, !speaking { signals.play(.directionTick(toRight:cue.toRight)) }
            } else if wasTicking {
                if directionTicks.isAligned { signals.play(.direction(signedDegrees:0)) } else { signals.stopDirection() }
            }
        } else { tolerance=Self.foundTolerance }
        if abs(error) <= tolerance { current.steadySince=current.steadySince ?? now } else { current.steadySince=nil }
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
