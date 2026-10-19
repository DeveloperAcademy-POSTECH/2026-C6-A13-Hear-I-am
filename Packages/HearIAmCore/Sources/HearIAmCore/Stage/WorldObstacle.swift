import Foundation

public struct WorldObstacle: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: ObstacleKind
    public var vertices: [Point3]
    /// Measured from the scan mesh while drafting; see ObjectHeight.
    public var height: Double?
    public var entryEdges: [Int]?
    public var exitEdges: [Int]?
    public init(id: UUID = UUID(), name: String, kind: ObstacleKind, vertices: [Point3], height: Double? = nil, entryEdges: [Int]? = nil, exitEdges: [Int]? = nil) {
        self.entryEdges=entryEdges; self.exitEdges=exitEdges
        self.id = id; self.name = name; self.kind = kind; self.vertices = vertices; self.height = height
    }
    public func projected(in area: StageArea) throws -> StageObstacle {
        guard vertices.allSatisfy({ abs($0.y-area.floorHeight) <= 0.10 }) else { throw LabError.invalid("기물의 바닥 높이를 다시 확인해주세요.") }
        let step=kind == .platform || kind == .stairs
        return try StageObstacle(id: id, name: name, kind: kind, passage: step ? .passable : .prohibited, vertices: vertices.map(area.floor), height: height, entryEdges: entryEdges, exitEdges: exitEdges)
    }
}
