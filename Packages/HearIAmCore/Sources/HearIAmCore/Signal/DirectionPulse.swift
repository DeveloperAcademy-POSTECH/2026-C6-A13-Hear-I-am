import Foundation

/// One vibration burst inside a direction pattern.
public struct DirectionPulse: Equatable, Sendable {
    public let time: Double
    public let duration: Double
    public let intensity: Float
    public let sharpness: Float
}
