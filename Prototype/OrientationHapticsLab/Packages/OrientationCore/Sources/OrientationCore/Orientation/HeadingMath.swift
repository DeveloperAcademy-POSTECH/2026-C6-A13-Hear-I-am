import Foundation

/// A row-major rotation that transforms reference-frame coordinates into device coordinates.
/// Copy all nine fields directly from `CMAttitude.rotationMatrix`.
public struct ReferenceToDeviceRotationMatrix: Sendable, Equatable {
    public let m11: Double, m12: Double, m13: Double
    public let m21: Double, m22: Double, m23: Double
    public let m31: Double, m32: Double, m33: Double

    public init(
        m11: Double, m12: Double, m13: Double,
        m21: Double, m22: Double, m23: Double,
        m31: Double, m32: Double, m33: Double
    ) {
        self.m11 = m11; self.m12 = m12; self.m13 = m13
        self.m21 = m21; self.m22 = m22; self.m23 = m23
        self.m31 = m31; self.m32 = m32; self.m33 = m33
    }

    fileprivate var isRotation: Bool {
        let rows = [[m11, m12, m13], [m21, m22, m23], [m31, m32, m33]]
        guard rows.joined().allSatisfy(\.isFinite) else { return false }
        let tolerance = 0.02
        for row in rows where abs(row.reduce(0) { $0 + $1 * $1 } - 1) > tolerance {
            return false
        }
        for first in 0..<3 {
            for second in (first + 1)..<3 {
                let dot = zip(rows[first], rows[second]).reduce(0) { $0 + $1.0 * $1.1 }
                if abs(dot) > tolerance { return false }
            }
        }
        let determinant = m11 * (m22 * m33 - m23 * m32)
            - m12 * (m21 * m33 - m23 * m31)
            + m13 * (m21 * m32 - m22 * m31)
        return abs(determinant - 1) <= tolerance
    }
}

public enum HeadingMath {
    /// Returns a clockwise heading in degrees, or nil when the posture cannot define a stable heading.
    ///
    /// Device +Z points out of the display. For a reference→device matrix R, the outward
    /// normal in the reference frame is transpose(R) × (0, 0, 1) = (m31, m32, m33).
    /// Project that normal onto the horizontal reference XY plane. Negating atan2 makes
    /// a physical right turn positive. This requires a Z-vertical Core Motion reference frame.
    /// It measures the attached phone's facing direction, not the wearer's head direction.
    public static func screenOutwardHeadingDegrees(
        referenceToDevice matrix: ReferenceToDeviceRotationMatrix,
        minimumHorizontalFraction: Double = 0.25
    ) -> Double? {
        guard matrix.isRotation,
              minimumHorizontalFraction.isFinite,
              minimumHorizontalFraction > 0,
              minimumHorizontalFraction <= 1 else { return nil }
        let norm = sqrt(matrix.m31 * matrix.m31 + matrix.m32 * matrix.m32 + matrix.m33 * matrix.m33)
        let horizontal = hypot(matrix.m31, matrix.m32)
        guard norm > 0, horizontal / norm >= minimumHorizontalFraction else { return nil }
        return wrapDegrees(-atan2(matrix.m32, matrix.m31) * 180 / .pi)
    }

    /// Wraps to [-180, 180]. At the exact antipode the input sign is retained.
    /// Nonfinite input produces NaN; callers must not treat that as a valid reading.
    public static func wrapDegrees(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return .nan }
        var result = degrees.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result == 0 ? 0 : result
    }

    /// The shortest signed change. Positive is a right turn.
    public static func signedDeltaDegrees(from old: Double, to new: Double) -> Double {
        guard old.isFinite, new.isFinite else { return .nan }
        return wrapDegrees(wrapDegrees(new) - wrapDegrees(old))
    }
}

public struct HeadingReading: Codable, Sendable, Equatable {
    /// Current direction relative to reset, wrapped to [-180, 180].
    public let relativeDegrees: Double
    /// Accumulated turn since reset. Does not jump at the ±180 boundary.
    public let continuousDegrees: Double

    public init(relativeDegrees: Double, continuousDegrees: Double) {
        self.relativeDegrees = relativeDegrees
        self.continuousDegrees = continuousDegrees
    }
}

/// Keep this value on the same actor/queue as sensor consumption.
/// Consecutive valid samples must be less than 180° apart; the shortest arc is assumed.
public struct RelativeHeadingTracker: Sendable {
    public private(set) var baselineHeadingDegrees: Double?
    public private(set) var reading: HeadingReading?
    private var previousAbsoluteDegrees: Double?

    public init() {}

    /// A successful reset returns zero. Invalid input leaves the old cycle untouched.
    @discardableResult
    public mutating func reset(absoluteHeadingDegrees: Double) -> HeadingReading? {
        guard absoluteHeadingDegrees.isFinite else { return nil }
        let baseline = HeadingMath.wrapDegrees(absoluteHeadingDegrees)
        baselineHeadingDegrees = baseline
        previousAbsoluteDegrees = baseline
        let zero = HeadingReading(relativeDegrees: 0, continuousDegrees: 0)
        reading = zero
        return zero
    }

    /// Returns nil until a baseline exists, or if the supplied sample is invalid.
    @discardableResult
    public mutating func update(absoluteHeadingDegrees: Double) -> HeadingReading? {
        guard absoluteHeadingDegrees.isFinite,
              let baseline = baselineHeadingDegrees,
              let previous = previousAbsoluteDegrees,
              let old = reading else { return nil }
        let absolute = HeadingMath.wrapDegrees(absoluteHeadingDegrees)
        let continuous = old.continuousDegrees
            + HeadingMath.signedDeltaDegrees(from: previous, to: absolute)
        let next = HeadingReading(
            relativeDegrees: HeadingMath.signedDeltaDegrees(from: baseline, to: absolute),
            continuousDegrees: continuous
        )
        reading = next
        previousAbsoluteDegrees = absolute
        return next
    }

    /// Clear on sensor restart or lifecycle interruption; require another explicit reset.
    public mutating func clear() {
        baselineHeadingDegrees = nil
        previousAbsoluteDegrees = nil
        reading = nil
    }
}
