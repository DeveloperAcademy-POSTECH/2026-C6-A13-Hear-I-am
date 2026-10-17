import Foundation

/// A spoken direction correction.
public enum Correction: String, Sendable {
    case left, right, back
    public var line: String {
        switch self {
        case .left: return SignalCopy.turnLeft
        case .right: return SignalCopy.turnRight
        case .back: return SignalCopy.turnBack
        }
    }
}
