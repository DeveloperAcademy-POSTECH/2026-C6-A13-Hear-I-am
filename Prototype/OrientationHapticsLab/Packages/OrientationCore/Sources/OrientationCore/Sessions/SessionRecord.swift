import Foundation

public enum SessionEndReason: String, Codable, Sendable {
    case reset
    case stopped
    case appInterrupted
}

public struct HapticEventRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let headingDegrees: Double
    public let triggerAngleDegrees: Double
    public let patternID: String

    public init(
        id: UUID = UUID(), date: Date, headingDegrees: Double,
        triggerAngleDegrees: Double, patternID: String
    ) {
        self.id = id
        self.date = date
        self.headingDegrees = headingDegrees
        self.triggerAngleDegrees = triggerAngleDegrees
        self.patternID = patternID
    }
}

/// An immutable completed cycle, suitable for local JSON persistence.
public struct SessionRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let endReason: SessionEndReason
    public let lastAngleDegrees: Double
    public let hapticEvents: [HapticEventRecord]
    public let walk: WalkSnapshot

    public var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }

    public init(
        id: UUID, startedAt: Date, endedAt: Date, endReason: SessionEndReason,
        lastAngleDegrees: Double, hapticEvents: [HapticEventRecord], walk: WalkSnapshot
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.endReason = endReason
        self.lastAngleDegrees = lastAngleDegrees
        self.hapticEvents = hapticEvents
        self.walk = walk
    }
}
