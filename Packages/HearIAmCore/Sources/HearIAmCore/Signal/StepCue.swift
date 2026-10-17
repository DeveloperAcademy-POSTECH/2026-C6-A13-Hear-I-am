import Foundation

/// "Step up / step down" announcement for a platform or stairs on the way to the target.
public struct StepCue: Equatable, Sendable {
    /// `over`: up and straight down again, said together when the platform is narrow on the way.
    public enum Kind: String, Sendable { case up, down, over }
    public let kind: Kind
    public let stairs: Bool
    public let obstacleID: UUID
    public let name: String
    /// Metres along the way to the target until the edge is crossed.
    public let distance: Double
    /// Metres between entering and leaving on the way, when announced from outside and the way leaves it.
    public let across: Double?
    /// Measured height above the floor, when the object was measured during preparation.
    public let height: Double?
    public init(kind: Kind, stairs: Bool, obstacleID: UUID, name: String, distance: Double, across: Double?=nil, height: Double?=nil) {
        self.kind=kind; self.stairs=stairs; self.obstacleID=obstacleID; self.name=name
        self.distance=distance; self.across=across; self.height=height
    }
    public var line: String {
        switch kind {
        case .up: return SignalCopy.stepUp(stairs:stairs)
        case .down: return SignalCopy.stepDown
        case .over: return SignalCopy.stepOver(stairs:stairs)
        }
    }
    public var detail: String {
        var text=String(format:"%@ %@ %.2fm",kind.rawValue,name,distance)
        if let across { text+=String(format:" across=%.2fm",across) }
        if let height { text+=String(format:" height=%.2fm",height) }
        return text
    }
}
