import Foundation

/// Where the walking screen's light and arrow point (#167). The light moves with 정면 찾기's easing; when it moves
/// follows the sound: it is centred from the moment the aligned chime rings and moves to the side when the ticks
/// start again, past the same release margin (`DirectionTickGate`). The arrow shows the same thing in 45° steps,
/// straight ahead while aligned, and changes step only once the bearing is clearly into the next one.
public struct WalkGlowDirection: Sendable {
    public enum Phase: Equatable, Sendable { case aligned, finding }
    public private(set) var phase: Phase = .finding
    /// The body-relative bearing of the next point (positive = to the right), or nil without a fresh pose.
    public private(set) var bearing: Double?
    /// The arrow, in 45° steps within -135...180 (0 = ahead, positive = to the right).
    public private(set) var arrowDegrees: Double = 0
    private var gate: DirectionTickGate
    /// How far past the halfway line between two steps the bearing must go before the arrow turns.
    public static let arrowHysteresisDegrees = 10.0

    public init(deadbandDegrees: Double = DirectionTickGate.defaultDeadbandDegrees) {
        gate = DirectionTickGate(deadbandDegrees: deadbandDegrees)
    }
    /// The angle at which the ticks, and with them the light, leave the middle again.
    public var departureDegrees: Double { gate.deadbandDegrees + gate.releaseMarginDegrees }

    public mutating func update(bearing: Double?, time: Double) {
        guard let bearing, bearing.isFinite, time.isFinite else { self.bearing = nil; return }
        self.bearing = bearing
        _ = gate.update(time: time, bearing: bearing)
        phase = gate.isAligned ? .aligned : .finding
        if phase == .aligned { arrowDegrees = 0; return }
        let off = abs(Self.wrap(bearing - arrowDegrees))
        if off > 22.5 + Self.arrowHysteresisDegrees {
            arrowDegrees = Self.wrap((bearing / 45).rounded() * 45)
            if arrowDegrees == -180 { arrowDegrees = 180 }
        }
    }
    public mutating func reset() {
        phase = .finding; bearing = nil; arrowDegrees = 0; gate.reset()
    }
    /// -180..<180.
    public static func wrap(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d >= 180 { d -= 360 } else if d < -180 { d += 360 }
        return d
    }
}
