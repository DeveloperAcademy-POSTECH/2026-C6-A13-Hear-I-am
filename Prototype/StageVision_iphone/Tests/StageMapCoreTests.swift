import Foundation
import simd

@main
struct StageMapCoreTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        guard value() else { fatalError("FAIL: \(label)") }
    }
    static func close(_ a: Double, _ b: Double, _ label: String, tolerance: Double = 1e-6) {
        check(abs(a - b) < tolerance, "\(label): \(a) vs \(b)")
    }
    static func area(_ pieces: [[MapPoint]]) -> Double { pieces.reduce(0) { $0 + abs(StageGeometry.signedArea($1)) } }
    @MainActor static func main() throws {
        let rect = [MapPoint(0, 0), MapPoint(8, 0), MapPoint(8, 6), MapPoint(0, 6)]
        check(StageGeometry.validate(rect) == nil, "rectangle")
        check(StageGeometry.validate(Array(rect.reversed())) == nil, "clockwise rectangle")
        close(StageGeometry.signedArea(rect), 48, "area")
        check(StageGeometry.validate(Array(rect.prefix(2))) != nil, "two points")
        check(StageGeometry.validate([MapPoint(0, 0), MapPoint(2, 2), MapPoint(0, 2), MapPoint(2, 0)])?.edges == [0, 2], "bow tie")
        check(StageGeometry.validate([MapPoint(0, 0), MapPoint(2, 0), MapPoint(1, 0), MapPoint(1, 2)]) != nil, "backtracking overlap")
        check(StageGeometry.validate([MapPoint(0, 0), MapPoint(2, 0), MapPoint(4, 0)]) != nil, "zero area")
        check(StageGeometry.validate([MapPoint(0, 0), MapPoint(0.01, 0), MapPoint(2, 2)]) != nil, "near duplicate")
        check(StageGeometry.validate([MapPoint(.nan, 0), MapPoint(1, 0), MapPoint(0, 1)]) != nil, "nonfinite")
        check(StageGeometry.validate([MapPoint(0, 0), MapPoint(4, 0), MapPoint(4, 4), MapPoint(2, 0), MapPoint(0, 4)]) != nil, "nonadjacent touching")
        check(StageGeometry.intersects(MapPoint(0, 0), MapPoint(3, 0), MapPoint(1, 0), MapPoint(4, 0)), "collinear overlap")
        check(StageGeometry.contains(MapPoint(0, 0), polygon: rect), "boundary included")
        check(!StageGeometry.contains(MapPoint(-0.01, 1), polygon: rect), "outside excluded")
        let collinear = [MapPoint(0, 0), MapPoint(4, 0), MapPoint(8, 0), MapPoint(8, 6), MapPoint(0, 6)]
        close(area(StageGeometry.triangles(collinear)), 48, "collinear triangulation")
        let concave = [MapPoint(0, 0), MapPoint(6, 0), MapPoint(6, 2), MapPoint(2, 2), MapPoint(2, 6), MapPoint(0, 6)]
        check(!StageGeometry.contains(MapPoint(4, 4), polygon: concave), "notch outside")
        close(area(StageGeometry.triangles(concave)), 20, "concave triangulation")
        let triangles = StageGeometry.triangles(rect)
        for width in [1.0, 1.5] {
            close(area(StageGeometry.riskPieces(polygon: rect, edge: 0, width: width, triangles: triangles)), 8 * width, "exact straight band \(width)")
            let pieces = StageGeometry.riskPieces(polygon: concave, edge: 2, width: width, triangles: StageGeometry.triangles(concave))
            check(!pieces.isEmpty, "concave band generated")
            for piece in pieces {
                for p in piece {
                    check(StageGeometry.contains(p, polygon: concave), "band clipped inside")
                    check(StageGeometry.distance(p, to: concave[2], concave[3]) <= width + 1e-6, "band within requested width")
                }
            }
        }
        for count in 5...32 {
            let star = (0..<count).map { i -> MapPoint in
                let angle = Double(i) * 2 * .pi / Double(count), radius = i % 2 == 0 ? 5.0 : 2.5
                return MapPoint(cos(angle) * radius, sin(angle) * radius)
            }
            close(area(StageGeometry.triangles(star)), abs(StageGeometry.signedArea(star)), "star triangulation \(count)")
            close(area(StageGeometry.triangles(Array(star.reversed()))), abs(StageGeometry.signedArea(star)), "reversed star \(count)")
        }
        let frame = StageFrame(origin: SIMD3(3, 2, 4), cameraForward: SIMD3(0, 0, 1))!
        check(frame.point(SIMD3(4, 2, 3)) == MapPoint(1, 1), "AR to stage axis mapping")
        check(simd_distance(simd_cross(frame.right, frame.back), SIMD3(0, 1, 0)) < 1e-6, "right handed frame")
        check(StageFrame(origin: .zero, cameraForward: SIMD3(0, -1, 0)) == nil, "reject vertical front")
        let hit = StageFrame.floorIntersection(origin: SIMD3(0, 2, 0), direction: simd_normalize(SIMD3(0, -1, -1)), height: 0)!
        close(Double(hit.z), -2, "virtual plane hit")
        check(hit.y == 0, "floor fixed")
        check(StageFrame.floorIntersection(origin: SIMD3(0, 2, 0), direction: SIMD3(1, 0, 0), height: 0) == nil, "parallel ray")
        check(StageFrame.floorIntersection(origin: SIMD3(0, 2, 0), direction: SIMD3(0, 1, 0), height: 0) == nil, "behind ray")
        check(StageFrame.floorIntersection(origin: SIMD3(0, 2, 0), direction: simd_normalize(SIMD3(1, -0.06, 0)), height: 0) == nil, "distant ray")
        var map = StageMap(points: rect)
        map.coordinateSystem.stageToARWorld = frame.matrix
        map.rebuildRiskZones()
        check(map.isRisk(MapPoint(4, 0.9)), "risk membership")
        check(!map.isRisk(MapPoint(4, 3)), "safe membership")
        check(!map.isRisk(MapPoint(-1, 0)), "outside not start position")
        let originalWorld = world(rect[0], map.coordinateSystem.stageToARWorld!)
        map.setFront(edge: 1)
        close(map.floorPolygon[1].y, 0, "new front start y")
        close(map.floorPolygon[2].y, 0, "new front end y")
        check(map.floorPolygon[0].y > 0, "interior toward +Y")
        check(simd_distance(world(map.floorPolygon[0], map.coordinateSystem.stageToARWorld!), originalWorld) < 1e-6, "front change preserves world coordinate")
        close(abs(StageGeometry.signedArea(map.floorPolygon)), 48, "front preserves area")
        try map.validated()
        map.rebuildRiskZones()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(map)
        let decoded = try decoder.decode(StageMap.self, from: data)
        try decoded.validated()
        check(decoded.floorPolygon == map.floorPolygon && decoded.riskZones == map.riskZones, "JSON round trip")
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        check((json["floorPolygon"] as? [[Double]])?.first?.count == 2, "schema coordinate arrays")
        check(json["unit"] as? String == "meter", "schema unit")
        map.boundarySegments[0].endIndex = 400
        do { try map.validated(); check(false, "reject malformed segment") } catch { check(true, "reject malformed segment") }
        var narrow = StageMap(points: [MapPoint(0, 0), MapPoint(1, 0), MapPoint(1, 0.5), MapPoint(0, 0.5)])
        narrow.rebuildRiskZones()
        close(area(narrow.riskZones[0].polygons), 0.5, "narrow floor fully covered")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("StageMapTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = StageMapStore(directory: temp)
        var editable = StageMap(points: rect)
        editable.rebuildRiskZones()
        store.replace(editable)
        store.insertPoint(after: 3)
        check(store.map?.floorPolygon.count == 5, "insert on closing edge")
        check(store.map?.boundarySegments.last?.endIndex == 0, "insert reindexes closure")
        store.undo()
        check(store.map?.floorPolygon == rect, "undo insert")
        store.edit { $0.boundarySegments[3].riskDistance = 1.5; $0.boundarySegments[0].riskEnabled = false }
        store.deletePoint(0)
        check(store.map?.floorPolygon.count == 3, "delete first vertex")
        check(store.map?.boundarySegments.last?.riskEnabled == true, "merge retains risk")
        check(store.map?.boundarySegments.last?.riskDistance == 1.5, "merge retains larger width")
        store.undo()
        check(store.map?.floorPolygon.count == 4, "undo delete")
        store.movePoint(1, to: MapPoint(-1, 5))
        check(store.map?.issue != nil, "invalid edit retained for repair")
        do { _ = try store.document(); check(false, "invalid export blocked") } catch { check(true, "invalid export blocked") }
        store.undo()
        store.edit { $0.setFront(edge: 1) }
        try store.map?.validated()
        store.undo()
        check(store.map?.floorPolygon == rect, "undo frame change")
        store.save()
        check(!store.isDirty, "saved clean")
        let restored = StageMapStore(directory: temp)
        check(restored.map?.floorPolygon == store.map?.floorPolygon, "restore latest JSON")
        check(restored.map?.riskZones == store.map?.riskZones, "restore risk geometry")
        try Data("broken JSON".utf8).write(to: temp.appendingPathComponent("latest.json"))
        let broken = StageMapStore(directory: temp)
        check(broken.map == nil && broken.message != nil, "corrupt saved map handled")
        print("PASS: \(checks) geometry, risk, coordinate, ray, JSON, editing and persistence checks")
    }
    static func world(_ p: MapPoint, _ m: [Double]) -> SIMD3<Double> {
        SIMD3(m[0] * p.x + m[4] * p.y + m[12], m[1] * p.x + m[5] * p.y + m[13], m[2] * p.x + m[6] * p.y + m[14])
    }
}
