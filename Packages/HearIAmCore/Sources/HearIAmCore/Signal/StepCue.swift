import Foundation

/// "Step up / step down" announcement for a platform or stairs on the way to the target.
public struct StepCue: Equatable, Sendable {
    public enum Kind: String, Sendable { case up, down }
    public let kind: Kind
    public let stairs: Bool
    public let obstacleID: UUID
    public let name: String
    /// Metres along the way to the target until the edge is crossed.
    public let distance: Double
    public var line: String { kind == .up ? SignalCopy.stepUp(stairs:stairs) : SignalCopy.stepDown }
    public var detail: String { String(format:"%@ %@ %.2fm",kind.rawValue,name,distance) }
}
