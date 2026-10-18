import Foundation

/// Obstacle warning stage. Closer stages repeat faster, like a parking sensor.
/// The distances that select a stage belong to the guidance rules, not to the sound.
public enum WarningLevel: Int, CaseIterable, Comparable, Sendable {
    case far=1, near, close
    /// Seconds from the start of one beep to the next.
    public var period: Double { [0.8,0.4,0.15][rawValue-1] }
    public var name: String { ["far","near","close"][rawValue-1] }
    /// Inside this distance an obstacle warns from any direction.
    public static let closeDistance=0.35
    public static func < (a: WarningLevel, b: WarningLevel) -> Bool { a.rawValue < b.rawValue }
}
