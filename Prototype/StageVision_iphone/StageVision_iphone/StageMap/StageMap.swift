import Foundation
import simd

struct StageCoordinateSystem: Codable, Equatable {
    var origin = [0.0, 0.0, 0.0]
    var xAxis = "stage-right"
    var yAxis = "stage-back"
    var zAxis = "up"
    var floorZ = 0.0
    /// Column-major StageMap -> ARKit transform: right, back, up, origin.
    /// Valid only in the capture session; it is NOT a relocalization artifact.
    var stageToARWorld: [Double]?
}

struct StageFrame {
    var origin: SIMD3<Float>
    var right: SIMD3<Float>
    var back: SIMD3<Float>

    init?(origin: SIMD3<Float>, cameraForward: SIMD3<Float>) {
        let horizontal = SIMD3<Float>(cameraForward.x, 0, cameraForward.z)
        guard simd_length(horizontal) > 0.25 else { return nil }
        self.origin = origin
        back = -simd_normalize(horizontal)
        right = simd_cross(back, SIMD3(0, 1, 0))
    }
    func point(_ world: SIMD3<Float>) -> MapPoint {
        let delta = world - origin
        return MapPoint(Double(simd_dot(delta, right)), Double(simd_dot(delta, back)))
    }
    var matrix: [Double] {
        [Double(right.x), 0, Double(right.z), 0,
         Double(back.x), 0, Double(back.z), 0,
         0, 1, 0, 0,
         Double(origin.x), Double(origin.y), Double(origin.z), 1]
    }
    static func floorIntersection(origin: SIMD3<Float>, direction: SIMD3<Float>, height: Float) -> SIMD3<Float>? {
        guard origin.y > height + 0.05, direction.y < -0.05 else { return nil }
        let t = (height - origin.y) / direction.y
        guard t > 0, t <= 20, t.isFinite else { return nil }
        let p = origin + t * direction
        guard p.x.isFinite, p.z.isFinite else { return nil }
        return SIMD3(p.x, height, p.z)
    }
}

enum BoundarySide: String, Codable, CaseIterable {
    case front, back, left, right, other
    var label: String {
        switch self {
        case .front: "앞"
        case .back: "뒤"
        case .left: "좌"
        case .right: "우"
        case .other: "기타"
        }
    }
}
struct BoundarySegment: Codable, Equatable {
    var startIndex: Int
    var endIndex: Int
    var side: BoundarySide = .other
    var riskEnabled = true
    var riskDistance = 1.0
}
struct StageQuality: Codable, Equatable {
    var tracking = "normal"
    // Unknown until field calibration; never invent a precision estimate.
    var boundaryUncertaintyMeters: Double? = nil
    var unverifiedSegmentIndexes: [Int] = []
    var virtualPlanePointIndexes: [Int] = []
    var trackingInterruptionCount = 0
    var manuallyEdited = false
    var source = "arkit-manual-boundary"
    var notes = ["경계 오차 미측정. 자동 위치 추적과 안전 보장 기능이 아닙니다."]
}
struct ReferenceAnchor: Codable, Equatable {
    var id: String
    var position: [Double]
}
struct RiskZone: Codable, Equatable {
    var segmentIndex: Int
    var distance: Double
    var polygons: [[MapPoint]]
}
struct StageMap: Codable, Equatable {
    var version = 1
    var stageId = UUID().uuidString
    var name = "새 무대"
    var venue = ""
    var unit = "meter"
    var savedAt = Date()
    var coordinateSystem = StageCoordinateSystem()
    var floorPolygon: [MapPoint]
    var originalFloorPolygon: [MapPoint]
    var boundarySegments: [BoundarySegment]
    var referenceAnchors = [ReferenceAnchor(id: "user-origin", position: [0, 0, 0])]
    var quality = StageQuality()
    var riskZoneMethod = "segment-distance-band-clipped-to-floor; round caps, 24 chords/semicircle; union of pieces"
    var riskZones: [RiskZone] = []
    var startPosition: MapPoint?

    init(points: [MapPoint]) {
        floorPolygon = points
        originalFloorPolygon = points
        boundarySegments = points.indices.map { BoundarySegment(startIndex: $0, endIndex: ($0 + 1) % points.count) }
    }
    var issue: PolygonIssue? { StageGeometry.validate(floorPolygon) }
    mutating func rebuildRiskZones() {
        let triangles = StageGeometry.triangles(floorPolygon)
        riskZones = boundarySegments.indices.compactMap { i in
            let s = boundarySegments[i]
            guard s.riskEnabled else { return nil }
            return RiskZone(segmentIndex: i, distance: s.riskDistance,
                            polygons: StageGeometry.riskPieces(polygon: floorPolygon, edge: i, width: s.riskDistance, triangles: triangles))
        }
    }
    func isRisk(_ p: MapPoint) -> Bool {
        guard StageGeometry.contains(p, polygon: floorPolygon) else { return false }
        return boundarySegments.contains {
            $0.riskEnabled && StageGeometry.distance(p, to: floorPolygon[$0.startIndex], floorPolygon[$0.endIndex]) <= $0.riskDistance
        }
    }
    mutating func reindex() {
        for i in boundarySegments.indices {
            boundarySegments[i].startIndex = i
            boundarySegments[i].endIndex = (i + 1) % floorPolygon.count
        }
        quality.manuallyEdited = true
        quality.unverifiedSegmentIndexes = Array(floorPolygon.indices)
        // These indexes refer to originalFloorPolygon and remain unchanged after edits.
        if let p = startPosition, !StageGeometry.contains(p, polygon: floorPolygon) { startPosition = nil }
    }
    /// Choose the selected edge's midpoint as origin and its outward normal as audience/front.
    mutating func setFront(edge: Int) {
        guard issue == nil, floorPolygon.indices.contains(edge) else { return }
        let a = floorPolygon[edge], b = floorPolygon[(edge + 1) % floorPolygon.count]
        let origin = (a + b) * 0.5
        let tangent = (b - a) * (1 / (b - a).length)
        let back = MapPoint(-tangent.y, tangent.x) * (StageGeometry.signedArea(floorPolygon) > 0 ? 1 : -1)
        let right = MapPoint(back.y, -back.x)
        func convert(_ p: MapPoint) -> MapPoint { MapPoint((p - origin).dot(right), (p - origin).dot(back)) }
        floorPolygon = floorPolygon.map(convert)
        originalFloorPolygon = originalFloorPolygon.map(convert)
        startPosition = startPosition.map(convert)
        referenceAnchors = referenceAnchors.map {
            let p = convert(MapPoint($0.position[0], $0.position[1]))
            return ReferenceAnchor(id: $0.id, position: [p.x, p.y, $0.position[2]])
        }
        referenceAnchors.removeAll { $0.id == "front-midpoint" }
        referenceAnchors.append(ReferenceAnchor(id: "front-midpoint", position: [0, 0, 0]))
        if let m = coordinateSystem.stageToARWorld, m.count == 16 {
            var n = m
            for row in 0..<3 {
                n[row] = m[row] * right.x + m[4 + row] * right.y
                n[4 + row] = m[row] * back.x + m[4 + row] * back.y
                n[12 + row] = m[12 + row] + m[row] * origin.x + m[4 + row] * origin.y
            }
            coordinateSystem.stageToARWorld = n
        }
        for i in boundarySegments.indices { boundarySegments[i].side = i == edge ? .front : .other }
        quality.manuallyEdited = true
    }
    func validated() throws {
        if let issue { throw StageMapError.invalid(issue.message) }
        if let originalIssue = StageGeometry.validate(originalFloorPolygon) {
            throw StageMapError.invalid("원본 경계: \(originalIssue.message)")
        }
        guard quality.unverifiedSegmentIndexes.allSatisfy({ floorPolygon.indices.contains($0) }),
              quality.virtualPlanePointIndexes.allSatisfy({ originalFloorPolygon.indices.contains($0) }),
              startPosition.map({ $0.x.isFinite && $0.y.isFinite && StageGeometry.contains($0, polygon: floorPolygon) }) ?? true
        else { throw StageMapError.invalid("품질 인덱스 또는 시작 위치가 유효하지 않습니다.") }
        guard version == 1, unit == "meter", boundarySegments.count == floorPolygon.count,
              coordinateSystem.origin == [0, 0, 0], coordinateSystem.floorZ == 0,
              coordinateSystem.xAxis == "stage-right", coordinateSystem.yAxis == "stage-back", coordinateSystem.zAxis == "up",
              coordinateSystem.stageToARWorld.map({ $0.count == 16 && $0.allSatisfy(\.isFinite) }) ?? true,
              referenceAnchors.allSatisfy({ $0.position.count == 3 && $0.position.allSatisfy(\.isFinite) }),
              boundarySegments.enumerated().allSatisfy({ i, s in
                  s.startIndex == i && s.endIndex == (i + 1) % floorPolygon.count && [1.0, 1.5].contains(s.riskDistance)
              }) else { throw StageMapError.invalid("StageMap 좌표계 또는 선분 데이터가 유효하지 않습니다.") }
    }
}
enum StageMapError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let s) = self { return s }; return nil }
}
