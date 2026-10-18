import Foundation

/// The warning to play right now and why: which obstacle, how far, and which way.
public struct ObstacleWarning: Equatable, Sendable {
    public let level: WarningLevel
    public let obstacleID: UUID
    public let name: String
    /// Metres to the obstacle's outline; 0 when the position is inside it.
    public let distance: Double
    /// Body-relative bearing to the closest outline point, positive on the right.
    public let bearing: Double
    /// For logs, e.g. "near 의자 0.52m bearing +34°".
    public var detail: String { String(format:"%@ %@ %.2fm bearing %+.0f°",level.name,name,distance,bearing) }
}
