import Foundation

/// Where the walking screen's light sits (#167). It follows the next point the way 정면 찾기 follows the chosen
/// front (`FrontDirectionPractice`): once the body faces the point the light stays centred, and it moves to the
/// side again only after the body turns clearly away, past the same departure angle. Following every small
/// change of the bearing made the light restless while walking (11/09 device test).
public struct WalkGlowDirection: Sendable {
    public enum Phase: Equatable, Sendable { case aligned, finding }
    public private(set) var phase: Phase = .finding
    /// The body-relative bearing of the next point (positive = to the right), or nil without a fresh pose.
    public private(set) var bearing: Double?
    private var gate: DirectionTickGate

    public init(deadbandDegrees: Double = DirectionTickGate.defaultDeadbandDegrees) {
        gate = DirectionTickGate(deadbandDegrees: deadbandDegrees)
    }
    /// The same angle 정면 찾기 asks the body to leave by before the front is looked for again.
    public var departureDegrees: Double { max(25, gate.deadbandDegrees + gate.releaseMarginDegrees + 10) }

    public mutating func update(bearing: Double?, time: Double) {
        guard let bearing, bearing.isFinite, time.isFinite else { self.bearing = nil; return }
        self.bearing = bearing
        if phase == .aligned {
            guard abs(bearing) >= departureDegrees else { return }
            gate.reset(); phase = .finding
        }
        _ = gate.update(time: time, bearing: bearing)
        if gate.isAligned { phase = .aligned }
    }
    public mutating func reset() {
        phase = .finding; bearing = nil; gate.reset()
    }
}
