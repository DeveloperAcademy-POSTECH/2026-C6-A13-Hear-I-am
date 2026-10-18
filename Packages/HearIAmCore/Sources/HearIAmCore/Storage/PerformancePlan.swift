import Foundation

/// A separate, schematic 3:2 canvas. Units are layout units, not a surveyed stage.
public struct PerformancePlan: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name = "새 공연 동선"
    public var updatedAt = Date()
    public private(set) var points: [FloorPoint] = []
    public private(set) var finished = false
    public var objects: [StageObstacle] = []
    public static let width = 12.0
    public static let depth = 8.0
    public init() {}
    public static var area: StageArea {
        // Fixed, known-valid schematic geometry.
        try! StageArea(corners: [Point3(0,0,0), Point3(12,0,0), Point3(12,0,-8), Point3(0,0,-8)])
    }
    public mutating func append(_ point: FloorPoint) throws {
        guard !finished, points.count < 6, point.valid, (-3...15).contains(point.x), (-1...9).contains(point.y) else {
            throw LabError.invalid("경로를 편집하려면 최신 점을 삭제해주세요. 최대 6점까지 가능합니다.")
        }
        if points.count == 1, !Self.area.contains(point, margin: 0.01) {
            throw LabError.invalid("첫 내부 지점 P1은 무대 안에 지정해주세요.")
        }
        // The current last point can be outside as a prospective destination;
        // adding another point would turn it into an interior waypoint.
        if points.count >= 2, let last = points.last, !Self.area.contains(last, margin: 0.01) {
            throw LabError.invalid("무대 밖의 마지막 점은 도착점으로 완료하거나 삭제해주세요.")
        }
        if let last = points.last, last.distance(to: point) < 0.05 { throw LabError.invalid("서로 다른 위치를 선택해주세요.") }
        points.append(point)
    }
    public mutating func undoPoint() {
        guard !points.isEmpty else { return }
        points.removeLast(); finished = false
    }
    public mutating func finishRoute() throws {
        guard points.count >= 3 else { throw LabError.invalid("출발점·내부 지점·도착점, 최소 3점이 필요합니다.") }
        let candidate = try StageRoute(area: Self.area, points: points, obstacles: objects, allowsOutsideEndpoints: true)
        let errors = candidate.conflicts(boundaryMargin: 0.01, obstacleClearance: 0.15)
        guard errors.isEmpty else { throw LabError.invalid(errors.joined(separator: "\n")) }
        finished = true
    }
    public mutating func addObject(at p: FloorPoint, platform: Bool) throws {
        let vertices = platform
            ? [FloorPoint(p.x-0.6,p.y-0.5),FloorPoint(p.x+0.6,p.y-0.5),FloorPoint(p.x+0.6,p.y+0.5),FloorPoint(p.x-0.6,p.y+0.5)]
            : [FloorPoint(p.x,p.y+0.6),FloorPoint(p.x-0.6,p.y-0.5),FloorPoint(p.x+0.6,p.y-0.5)]
        guard vertices.allSatisfy({Self.area.contains($0)}) else { throw LabError.invalid("기물이 무대 안에 들어오도록 배치해주세요.") }
        objects.append(try StageObstacle(name: platform ? "단상" : "장애물", kind: platform ? .platform : .other,
                                         passage: platform ? .passable : .prohibited, vertices: vertices))
    }
    public mutating func moveObject(_ id: UUID, to p: FloorPoint) throws {
        guard let i = objects.firstIndex(where: {$0.id == id}) else { return }
        let vertices = objects[i].vertices
        let center = FloorPoint(vertices.map(\.x).reduce(0,+)/Double(vertices.count), vertices.map(\.y).reduce(0,+)/Double(vertices.count))
        let moved = vertices.map { FloorPoint($0.x+p.x-center.x, $0.y+p.y-center.y) }
        guard moved.allSatisfy({Self.area.contains($0)}) else { throw LabError.invalid("기물을 무대 안에 배치해주세요.") }
        objects[i].vertices = moved
    }
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80, finished else { throw LabError.invalid("이름을 입력하고 경로를 완료해주세요.") }
        let route = try StageRoute(area: Self.area, points: points, obstacles: objects, allowsOutsideEndpoints: true)
        let errors = route.conflicts(boundaryMargin: 0.01, obstacleClearance: 0.15)
        guard errors.isEmpty else { throw LabError.invalid(errors.joined(separator: "\n")) }
    }
}
