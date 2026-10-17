import Foundation

public struct GuidanceCue: Equatable, Sendable {
    public let sector: Int
    public let distance: Double
    public var direction: String { ["앞","오른쪽 앞","오른쪽","오른쪽 뒤","뒤","왼쪽 뒤","왼쪽","왼쪽 앞"][sector] }
    public var symbol: String { ["arrow.up","arrow.up.right","arrow.right","arrow.down.right","arrow.down","arrow.down.left","arrow.left","arrow.up.left"][sector] }
    public var speech: String { String(format:"%@, %.1f미터.",direction,distance) }
    public init?(position: FloorPoint, goal: FloorPoint, headingDegrees: Double, sector: Int? = nil) {
        guard position.valid, goal.valid, headingDegrees.isFinite else { return nil }
        let angle=StageHeading.bearing(from:position,to:goal,headingDegrees:headingDegrees)
        self.sector=sector.flatMap { (0..<8).contains($0) ? $0 : nil } ?? StageHeading.sector(angle)
        distance=position.distance(to:goal)
    }
}
