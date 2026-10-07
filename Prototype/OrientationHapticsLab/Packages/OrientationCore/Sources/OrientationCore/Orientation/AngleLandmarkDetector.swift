import Foundation

public struct AngleCue: Codable, Sendable, Identifiable, Hashable {
    /// A signed angle in degrees; positive means right, negative means left.
    public let signedDegrees: Int
    public var id: Int { signedDegrees }
    public var magnitudeDegrees: Int { signedDegrees == .min ? .max : abs(signedDegrees) }
    public var isRight: Bool { signedDegrees > 0 }
    public var label: String {
        guard (-179...179).contains(signedDegrees) else { return "유효하지 않은 각도" }
        if signedDegrees == 0 { return "정면 0°" }
        return "\(isRight ? "오른쪽" : "왼쪽") \(magnitudeDegrees)°"
    }

    public init(signedDegrees: Int) {
        self.signedDegrees = signedDegrees
    }

    public static let defaults: [AngleCue] = [-90, -45, -30, 30, 45, 90].map {
        AngleCue(signedDegrees: $0)
    }
}

/// Detects entry into an angle window or a crossing between samples, with hysteresis.
/// Pass a wrapped relative heading from `RelativeHeadingTracker`; shortest-arc movement
/// between consecutive samples is assumed. Sensor discontinuities must call `reset()`.
public struct AngleLandmarkDetector: Sendable {
    public private(set) var cues: [AngleCue]
    public let entryToleranceDegrees: Double
    public let rearmToleranceDegrees: Double
    private var latched: Set<Int> = []
    private var previousWrappedDegrees: Double?
    private var previousContinuousDegrees: Double?

    public init(
        cues: [AngleCue] = AngleCue.defaults,
        entryToleranceDegrees: Double = 3,
        rearmToleranceDegrees: Double = 6
    ) {
        self.cues = Self.validCues(cues)
        let entry = entryToleranceDegrees.isFinite && (0..<90).contains(entryToleranceDegrees)
            ? entryToleranceDegrees : 3
        self.entryToleranceDegrees = entry
        self.rearmToleranceDegrees = rearmToleranceDegrees.isFinite
            && rearmToleranceDegrees > entry && rearmToleranceDegrees < 180
            ? rearmToleranceDegrees : max(6, entry + 1)
    }

    /// Use this for settings toggles. Drops interpolation history so changing settings
    /// cannot create a crossing from an old sensor sample.
    public mutating func setCues(_ cues: [AngleCue]) {
        self.cues = Self.validCues(cues)
        reset()
    }

    public mutating func reset() {
        latched.removeAll()
        previousWrappedDegrees = nil
        previousContinuousDegrees = nil
    }

    /// Returns at most one cue: the last newly reached landmark along this movement.
    /// All encountered landmarks are consumed immediately; there is no pending cue queue.
    /// Invalid input breaks interpolation, preventing a later sample from crossing an unseen arc.
    @discardableResult
    public mutating func update(relativeDegrees: Double) -> AngleCue? {
        guard relativeDegrees.isFinite else {
            previousWrappedDegrees = nil
            previousContinuousDegrees = nil
            return nil
        }
        let wrapped = HeadingMath.wrapDegrees(relativeDegrees)
        let previous = previousContinuousDegrees
        let delta = previousWrappedDegrees.map {
            HeadingMath.signedDeltaDegrees(from: $0, to: wrapped)
        } ?? 0
        let current = previous.map { $0 + delta } ?? wrapped
        var latest: (cue: AngleCue, progress: Double)?

        for cue in cues {
            let base = Double(cue.signedDegrees)
            let occurrence = base + 360 * ((current - base) / 360).rounded()
            let distance = abs(current - occurrence)
            if latched.contains(cue.id) {
                if distance > rearmToleranceDegrees { latched.remove(cue.id) }
                continue
            }

            let isInside = distance <= entryToleranceDegrees
            let crossed: Bool
            if let previous, delta > 0 {
                crossed = previous < occurrence && occurrence <= current
            } else if let previous, delta < 0 {
                crossed = current <= occurrence && occurrence < previous
            } else {
                crossed = false
            }
            guard isInside || crossed else { continue }

            // If a fast sample already exited the outer window, it is immediately rearmed.
            if distance <= rearmToleranceDegrees { latched.insert(cue.id) }
            let progress: Double
            if let previous, abs(delta) > 0 {
                progress = crossed ? abs(occurrence - previous) / abs(delta) : 1
            } else {
                progress = -distance
            }
            if latest == nil || progress > latest!.progress {
                latest = (cue, progress)
            }
        }

        previousWrappedDegrees = wrapped
        previousContinuousDegrees = current
        return latest?.cue
    }

    private static func validCues(_ cues: [AngleCue]) -> [AngleCue] {
        // Exclude the ambiguous antipode and invalid values without trapping on Int.min.
        Array(Set(cues.filter { (-179...179).contains($0.signedDegrees) && $0.signedDegrees != 0 }))
            .sorted { $0.signedDegrees < $1.signedDegrees }
    }
}
