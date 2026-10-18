import Foundation

/// Angle helpers carried over from PoC1 (branch poc/1-orientation-haptics). Positive is a right turn.
public enum HeadingMath {
    /// Wraps to [-180, 180]. Nonfinite input produces NaN; callers must not treat that as a reading.
    public static func wrapDegrees(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return .nan }
        var result=degrees.truncatingRemainder(dividingBy:360)
        if result > 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result == 0 ? 0 : result
    }
    /// The shortest signed change from `old` to `new`.
    public static func signedDeltaDegrees(from old: Double, to new: Double) -> Double {
        guard old.isFinite, new.isFinite else { return .nan }
        return wrapDegrees(wrapDegrees(new)-wrapDegrees(old))
    }
    /// Clockwise heading of the phone's screen normal, or nil when the phone lies too flat to define one.
    /// Needs a Z-vertical Core Motion reference frame. For a reference→device matrix R the screen
    /// normal in the reference frame is (m31, m32, m33); its horizontal part gives the heading.
    /// Only differences between headings are meaningful; the zero is arbitrary.
    public static func screenHeadingDegrees(_ m: ReferenceToDeviceRotation, minimumHorizontalFraction: Double=0.25) -> Double? {
        guard m.isRotation else { return nil }
        let norm=(m.m31*m.m31+m.m32*m.m32+m.m33*m.m33).squareRoot(), horizontal=hypot(m.m31,m.m32)
        guard norm > 0, horizontal/norm >= minimumHorizontalFraction else { return nil }
        return wrapDegrees(-atan2(m.m32,m.m31)*180 / .pi)
    }
}
