import Foundation

public enum RotationRecognition {
    /// Core Motion yaw is counterclockwise; the UI uses clockwise-positive degrees.
    public static func clockwiseDegrees(yaw: Double, referenceYaw: Double) -> Double {
        normalized((referenceYaw - yaw) * 180 / .pi)
    }
    public static func normalized(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return .nan }
        let angle = degrees.truncatingRemainder(dividingBy: 360)
        return angle > 180 ? angle - 360 : angle < -180 ? angle + 360 : angle
    }
    public static func target(for direction: Direction) -> Double {
        switch direction { case .front: return 0; case .back: return 180; case .left: return -90; case .right: return 90 }
    }
}

/// The held angle is submitted regardless of which direction the cue requested.
public struct RotationAnswer: Equatable {
    public let degrees: Double
    public var direction: Direction? {
        Direction.allCases.first {
            abs(RotationRecognition.normalized(degrees - RotationRecognition.target(for: $0))) <= 20
        }
    }
    public func isCorrect(for expected: Direction) -> Bool { direction == expected }
}

/// One second of stillness submits once, including an incorrect or diagonal response.
public struct RotationHold {
    public let requiredDuration: Double = 1
    private var beganAt: Double?
    private var anchorDegrees: Double?
    private var previousTime: Double?
    private var didComplete = false
    public init() {}

    public mutating func update(degrees: Double, angularSpeed: Double, faceUp: Bool, time: Double) -> RotationAnswer? {
        guard !didComplete else { return nil }
        guard degrees.isFinite, angularSpeed.isFinite, time.isFinite, faceUp,
              abs(angularSpeed) <= 15 else {
            reset(); return nil
        }
        if let previousTime, time <= previousTime || time - previousTime > 0.25 { reset() }
        if let anchorDegrees, abs(RotationRecognition.normalized(degrees - anchorDegrees)) > 10 { reset() }
        previousTime = time
        if beganAt == nil { beganAt = time; anchorDegrees = degrees }
        if time - (beganAt ?? time) >= requiredDuration {
            didComplete = true
            return RotationAnswer(degrees: RotationRecognition.normalized(degrees))
        }
        return nil
    }
    private mutating func reset() {
        beganAt = nil; anchorDegrees = nil; previousTime = nil
    }
}
