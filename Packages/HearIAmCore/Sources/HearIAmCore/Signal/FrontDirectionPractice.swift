import Foundation

/// A short, relative-heading exercise. The reference belongs to one uninterrupted motion session.
/// Uses the same direction gate as stage guidance; does not modify any guidance preference.
public struct FrontDirectionPractice: Sendable {
    public enum Phase: Equatable, Sendable { case needsReference, turnAway, finding, completed }
    public private(set) var phase: Phase = .needsReference
    public private(set) var referenceHeading: Double?
    public private(set) var bearing: Double?
    private var gate: DirectionTickGate
    private var lastTime: Double?

    public init(deadbandDegrees: Double = DirectionTickGate.defaultDeadbandDegrees) {
        gate = DirectionTickGate(deadbandDegrees: deadbandDegrees)
    }
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
        referenceHeading = nil; bearing = nil; phase = .needsReference
        gate.reset(); lastTime = nil
    }
    /// Keeps the reference only while the original sensor session is still running.
    public mutating func repeatExercise() {
        guard referenceHeading != nil else { return }
        gate.reset(); lastTime = nil; phase = .turnAway
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
        guard phase != .completed else { return nil }
        if phase == .turnAway {
            guard abs(delta) >= departureDegrees else { return nil }
            phase = .finding
        }
        let cue = gate.update(time: time, bearing: delta)
        if gate.isAligned { phase = .completed }
        return cue
    }
}
