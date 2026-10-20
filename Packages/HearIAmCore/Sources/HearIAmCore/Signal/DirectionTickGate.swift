import Foundation

/// Continuous angle-proportional direction feedback (#44):
/// - Within `±deadbandDegrees` of the next target: silent (stops ticking immediately).
/// - Outside the deadband: speaks "왼쪽" or "오른쪽" once on entry (or if turning the opposite side),
///   and emits a short woodblock click ("톡") whose interval shrinks as the body approaches the target angle.
/// - Once aligned, ticking starts again only past `deadbandDegrees + releaseMarginDegrees`, so sway at the
///   edge does not restart it (10/20: the margin was documented but not applied).
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
    /// True from entering the deadband until leaving it by the release margin.
    private(set) public var isAligned=false
    private var lastTickTime: Double?

    public init(deadbandDegrees: Double = Self.defaultDeadbandDegrees, releaseMarginDegrees: Double = 3.0) {
        self.deadbandDegrees = max(3, min(45, deadbandDegrees))
        self.releaseMarginDegrees = max(0, min(15, releaseMarginDegrees))
    }

    public mutating func reset() {
        activeSide = nil
        lastTickTime = nil
        isAligned = false
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

        // Inside the deadband, or still within the release margin after being inside: aligned, silent.
        // Right after reset (a new target) only the deadband applies.
        if absAngle <= deadbandDegrees || (isAligned && absAngle <= deadbandDegrees + releaseMarginDegrees) {
            activeSide = nil
            lastTickTime = nil
            isAligned = true
            return nil
        }
        isAligned = false

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
