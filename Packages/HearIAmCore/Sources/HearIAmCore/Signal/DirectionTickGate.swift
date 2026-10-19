import Foundation

/// Continuous angle-proportional direction feedback (#44):
/// - Within `±deadbandDegrees` of the next target: silent (stops ticking immediately).
/// - Outside the deadband: speaks "왼쪽" or "오른쪽" once on entry (or if turning the opposite side),
///   and emits a short woodblock click ("톡") whose interval shrinks as the body approaches the target angle.
public struct DirectionTickGate: Sendable {
    public struct Cue: Equatable, Sendable {
        public let toRight: Bool
        public let spokenWord: String?
        public let shouldTick: Bool
        public let interval: Double
        public var word: String { toRight ? SignalCopy.right : SignalCopy.left }
    }

    public static let defaultDeadbandDegrees = 12.0
    public static let minInterval = 0.14
    public static let maxInterval = 0.70

    public var deadbandDegrees: Double
    /// Hysteresis margin so slight sway right at the deadband edge does not re-trigger speech immediately.
    public var releaseMarginDegrees: Double
    private(set) public var activeSide: Bool?
    private var lastTickTime: Double?

    public init(deadbandDegrees: Double = Self.defaultDeadbandDegrees, releaseMarginDegrees: Double = 3.0) {
        self.deadbandDegrees = max(3, min(45, deadbandDegrees))
        self.releaseMarginDegrees = max(0, min(15, releaseMarginDegrees))
    }

    public mutating func reset() {
        activeSide = nil
        lastTickTime = nil
    }

    /// Interval between ticks for a given absolute bearing error in `[deadbandDegrees, 180]`.
    public func interval(forAbsBearing absAngle: Double) -> Double {
        let span = max(1.0, 180.0 - deadbandDegrees)
        let normalized = max(0.0, min(1.0, (absAngle - deadbandDegrees) / span))
        return Self.minInterval + normalized * (Self.maxInterval - Self.minInterval)
    }

    /// Evaluates the current body-relative target bearing (positive = target is on the right).
    /// Returns `nil` when aligned within the deadband (caller should stop any direction tick).
    public mutating func update(time: Double, bearing: Double) -> Cue? {
        guard time.isFinite, bearing.isFinite else {
            reset()
            return nil
        }
        let angle = HeadingMath.wrapDegrees(bearing)
        let absAngle = abs(angle)

        // Inside the deadband: aligned with the target direction -> immediate silence.
        if absAngle <= deadbandDegrees {
            reset()
            return nil
        }

        // If not yet active, require crossing `deadbandDegrees + releaseMarginDegrees` when re-entering from aligned,
        // except on the very first observation after reset/target change where `deadbandDegrees` applies directly.
        let toRight = angle > 0
        let interval = interval(forAbsBearing: absAngle)

        if activeSide != toRight {
            activeSide = toRight
            lastTickTime = time
            let word = toRight ? SignalCopy.right : SignalCopy.left
            return Cue(toRight: toRight, spokenWord: word, shouldTick: true, interval: interval)
        }

        let shouldTick: Bool
        if let last = lastTickTime {
            if time - last >= interval {
                lastTickTime = time
                shouldTick = true
            } else {
                shouldTick = false
            }
        } else {
            lastTickTime = time
            shouldTick = true
        }

        return Cue(toRight: toRight, spokenWord: nil, shouldTick: shouldTick, interval: interval)
    }
}
