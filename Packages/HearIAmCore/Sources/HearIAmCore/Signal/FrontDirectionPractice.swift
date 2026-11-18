import Foundation

/// A short, relative-heading exercise. The reference belongs to one uninterrupted motion session.
/// Judges the front exactly like a point's facing in stage guidance: ±`RouteGuide.facingToleranceDegrees`
/// with no release margin, held for the same one-second dwell (`DepartureGate`), so the front learned here
/// is the front the performer will be held to on stage. Does not modify any guidance preference.
public struct FrontDirectionPractice: Sendable {
    public enum Phase: Equatable, Sendable { case needsReference, turnAway, finding, completed }
    public private(set) var phase: Phase = .needsReference
    public private(set) var referenceHeading: Double?
    public private(set) var bearing: Double?
    /// True once the front has been found in this session; turning away afterwards starts another trial by itself.
    public private(set) var completedOnce = false
    private var gate: DirectionTickGate
    private var hold = DepartureGate()
    private var lastTime: Double?

    public init(toleranceDegrees: Double = RouteGuide.facingToleranceDegrees) {
        gate = DirectionTickGate(deadbandDegrees: toleranceDegrees, releaseMarginDegrees: 0)
    }
    /// Half-width of the band that counts as facing the front.
    public var toleranceDegrees: Double { gate.deadbandDegrees }
    /// Deliberately leave the alignment band before a return can count as success.
    public var departureDegrees: Double { max(25, gate.deadbandDegrees + gate.releaseMarginDegrees + 10) }

    @discardableResult public mutating func setReference(_ heading: Double) -> Bool {
        reset()
        guard heading.isFinite else { return false }
        referenceHeading = HeadingMath.wrapDegrees(heading)
        bearing = 0
        phase = .turnAway
        return true
    }
    public mutating func reset() {
        referenceHeading = nil; bearing = nil; phase = .needsReference; completedOnce = false
        gate.reset(); hold.reset(); lastTime = nil
    }
    /// Keeps the reference only while the original sensor session is still running.
    public mutating func repeatExercise() {
        guard referenceHeading != nil else { return }
        gate.reset(); hold.reset(); lastTime = nil; phase = .turnAway
    }
    public mutating func update(heading: Double?, time: Double) -> DirectionTickGate.Cue? {
        guard let heading, heading.isFinite, time.isFinite,
              lastTime.map({ time > $0 }) ?? true else {
            reset(); return nil
        }
        lastTime = time
        guard let referenceHeading else { return nil }
        let delta = HeadingMath.signedDeltaDegrees(from: heading, to: referenceHeading)
        bearing = delta
        // Found the front: stay there until the body turns away again, then find it again without any button.
        if phase == .completed {
            guard abs(delta) >= departureDegrees else { return nil }
            gate.reset(); hold.reset(); phase = .finding
        }
        if phase == .turnAway {
            guard abs(delta) >= departureDegrees else { return nil }
            phase = .finding
        }
        let cue = gate.update(time: time, bearing: delta)
        // Inside the band the cues fall silent at once, but the front only counts after a steady second there.
        if hold.observe(time: time, eligible: gate.isAligned) {
            hold.reset(); phase = .completed; completedOnce = true
        }
        return cue
    }
}
