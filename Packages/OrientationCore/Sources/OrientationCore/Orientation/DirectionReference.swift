import Foundation

/// One fixed reset reference shared by the angle display, clock display and outputs.
public enum DirectionReference {
    public static let signedLandmarks = [0, 30, 60, 90, 120, 150, 180, -150, -120, -90, -60, -30]

    public static func clockwiseDegrees(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return .nan }
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped == 0 ? 0 : wrapped
    }

    public static func nearestHour(_ degrees: Double) -> Int? {
        let clockwise = clockwiseDegrees(degrees)
        guard clockwise.isFinite else { return nil }
        let hour = Int((clockwise / 30).rounded()) % 12
        return hour == 0 ? 12 : hour
    }

    /// Only exact 30° landmarks in the signed domain are accepted by signal outputs.
    public static func landmark(_ degrees: Double) -> Int? {
        guard degrees.isFinite, (-180...180).contains(degrees) else { return nil }
        let canonical = abs(degrees + 180) < 0.001 ? 180 : degrees
        return signedLandmarks.first { abs(Double($0) - canonical) < 0.001 }
    }

    public static func clockLabel(_ degrees: Double) -> String {
        nearestHour(degrees).map { "\($0)시 방향" } ?? "방향 확인 필요"
    }

    public static func angleSpeech(_ degrees: Int) -> String {
        guard (-180...180).contains(degrees) else { return "방향 확인 필요" }
        if degrees == 0 { return "정면" }
        if abs(degrees) == 180 { return "뒤쪽 180도" }
        return "\(degrees < 0 ? "왼쪽" : "오른쪽") \(abs(degrees))도"
    }
}
