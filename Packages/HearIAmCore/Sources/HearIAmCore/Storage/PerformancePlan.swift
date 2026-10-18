import Foundation
import simd

/// A scaled movement segment between two consecutive waypoints in real stage metres.
public struct PlanSegment: Equatable, Identifiable, Sendable {
    public var id: String { "\(fromIndex)->\(toIndex)" }
    public let fromIndex: Int
    public let toIndex: Int
    public let distanceMeters: Double
    /// Angle in degrees relative to audience front (0° = toward audience, + = performer's right, - = performer's left).
    public let angleDegrees: Double

    public init(fromIndex: Int, toIndex: Int, distanceMeters: Double, angleDegrees: Double) {
        self.fromIndex = fromIndex
        self.toIndex = toIndex
        self.distanceMeters = distanceMeters
        self.angleDegrees = angleDegrees
    }
}

/// A separate, schematic 3:2 canvas that scales to real stage dimensions (stageWidth × stageDepth metres).
public struct PerformancePlan: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var name = "새 공연 동선"
    public var updatedAt = Date()
    public private(set) var points: [FloorPoint] = []
    public private(set) var finished = false
    public var objects: [StageObstacle] = []
    public var stageWidth = PerformancePlan.width
    public var stageDepth = PerformancePlan.depth
    public static let width = 12.0
    public static let depth = 8.0
    public static let dimensionRange = 1.0...100.0
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case id, name, updatedAt, points, finished, objects, stageWidth, stageDepth
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        points = try c.decode([FloorPoint].self, forKey: .points)
        finished = try c.decode(Bool.self, forKey: .finished)
        objects = try c.decode([StageObstacle].self, forKey: .objects)
        stageWidth = try c.decodeIfPresent(Double.self, forKey: .stageWidth) ?? Self.width
        stageDepth = try c.decodeIfPresent(Double.self, forKey: .stageDepth) ?? Self.depth
    }

    public static var area: StageArea {
        // Fixed, known-valid schematic geometry.
        try! StageArea(corners: [Point3(0,0,0), Point3(12,0,0), Point3(12,0,-8), Point3(0,0,-8)])
    }
    public var hasValidDimensions: Bool {
        stageWidth.isFinite && stageDepth.isFinite &&
        Self.dimensionRange.contains(stageWidth) && Self.dimensionRange.contains(stageDepth)
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
        objects.append(try StageObstacle(name: platform ? "단상" : "장애물", kind: platform ? .platform : .other, vertices: vertices))
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
        guard hasValidDimensions else { throw LabError.invalid("무대 가로·세로 크기는 1m~100m 사이로 입력해주세요.") }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80, finished else { throw LabError.invalid("이름을 입력하고 경로를 완료해주세요.") }
        let route = try StageRoute(area: Self.area, points: points, obstacles: objects, allowsOutsideEndpoints: true)
        let errors = route.conflicts(boundaryMargin: 0.01, obstacleClearance: 0.15)
        guard errors.isEmpty else { throw LabError.invalid(errors.joined(separator: "\n")) }
    }

    // MARK: - Dimension Scaling & Zero-Point Calibration

    /// Converts a schematic canvas coordinate (12×8) into real stage floor metres (stageWidth×stageDepth).
    public func scaledPoint(_ point: FloorPoint) -> FloorPoint {
        FloorPoint(point.x * (stageWidth / Self.width), point.y * (stageDepth / Self.depth))
    }

    /// All route points scaled to real stage metres.
    public func scaledPoints() -> [FloorPoint] {
        points.map(scaledPoint)
    }

    /// Route points expressed as relative metre offsets from the starting point P0.
    public func relativePointsFromStart() -> [FloorPoint] {
        let scaled = scaledPoints()
        guard let first = scaled.first else { return [] }
        return scaled.map { FloorPoint($0.x - first.x, $0.y - first.y) }
    }

    /// Computes physical distance (m) and angle (degrees relative to audience front 0°) for each segment.
    public func scaledSegments() -> [PlanSegment] {
        let scaled = scaledPoints()
        guard scaled.count >= 2 else { return [] }
        return (0..<(scaled.count - 1)).map { i in
            let start = scaled[i], end = scaled[i + 1]
            let dx = end.x - start.x
            let dy = end.y - start.y
            let distance = hypot(dx, dy)
            // Audience front is -Y; performer's right when facing audience is -X.
            let degrees = atan2(-dx, -dy) * 180.0 / .pi
            return PlanSegment(fromIndex: i, toIndex: i + 1, distanceMeters: distance, angleDegrees: degrees)
        }
    }

    /// Obstacles scaled proportionally to real stage metres.
    public func scaledObjects() throws -> [StageObstacle] {
        try objects.map {
            try StageObstacle(id: $0.id, name: $0.name, kind: $0.kind, passage: $0.passage, vertices: $0.vertices.map(scaledPoint))
        }
    }

    /// Builds a calibrated StageArea, StageFrame, StageRoute, and GuideSettings anchored so that
    /// the performer's current floor position `startWorld` corresponds to `points[0]` (start)
    /// and horizontal `cameraForward` faces the audience (heading 0°).
    public func calibratedStage(startWorld: Point3, cameraForward: Point3) throws -> (area: StageArea, frame: StageFrame, route: StageRoute, settings: GuideSettings) {
        try validate()
        guard startWorld.valid, cameraForward.valid else {
            throw LabError.invalid("현재 위치와 정면 방향을 확인할 수 없습니다.")
        }
        let horizontal = SIMD3<Double>(cameraForward.x, 0, cameraForward.z)
        let horizontalLen = simd_length(horizontal)
        // Audience direction in world X/Z is horizontal camera forward; fallback to -Z if held flat.
        let f = horizontalLen >= 0.05 ? (horizontal / horizontalLen) : SIMD3<Double>(0, 0, -1)
        let back = FloorPoint(-f.x, -f.z)
        // Audience-right (+stage X) is (-back.y, back.x) = (f.z, -f.x).
        let right = FloorPoint(f.z, -f.x)

        let startFloor = scaledPoint(points[0])
        let floorY = startWorld.y
        let frontLeftX = startWorld.x - startFloor.x * right.x - startFloor.y * back.x
        let frontLeftZ = startWorld.z - startFloor.x * right.y - startFloor.y * back.y

        func worldCorner(_ u: Double, _ v: Double) -> Point3 {
            Point3(frontLeftX + u * right.x + v * back.x, floorY, frontLeftZ + u * right.y + v * back.y)
        }
        let corners = [
            worldCorner(0, 0),
            worldCorner(stageWidth, 0),
            worldCorner(stageWidth, stageDepth),
            worldCorner(0, stageDepth)
        ]
        let area = try StageArea(corners: corners)
        let origin = area.world(FloorPoint(0, 0))
        let front = area.world(FloorPoint(0, -1))
        let frame = try StageFrame(origin: origin, front: front)
        let route = try StageRoute(area: area, points: scaledPoints(), obstacles: try scaledObjects(), allowsOutsideEndpoints: true)

        let scale = min(stageWidth / Self.width, stageDepth / Self.depth)
        var settings = GuideSettings()
        settings.boundaryMargin = 0.01 * scale
        settings.obstacleClearance = min(0.35, 0.15 * scale)
        return (area, frame, route, settings)
    }
}
