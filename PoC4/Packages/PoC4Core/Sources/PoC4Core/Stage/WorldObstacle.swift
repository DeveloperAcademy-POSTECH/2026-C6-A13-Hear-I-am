import Foundation

public struct WorldObstacle: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: ObstacleKind
    public var vertices: [Point3]
    public init(id: UUID = UUID(), name: String, kind: ObstacleKind, vertices: [Point3]) {
        self.id = id; self.name = name; self.kind = kind; self.vertices = vertices
    }
    public func projected(in area: StageArea) throws -> StageObstacle {
        guard vertices.allSatisfy({ abs($0.y-area.floorHeight) <= 0.10 }) else { throw LabError.invalid("기물의 바닥 높이를 다시 확인해주세요.") }
        return try StageObstacle(id: id, name: name, kind: kind, vertices: vertices.map(area.floor))
    }
}
