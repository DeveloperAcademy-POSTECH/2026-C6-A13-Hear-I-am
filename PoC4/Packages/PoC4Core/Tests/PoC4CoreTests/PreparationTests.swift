import XCTest
@testable import PoC4Core

final class PreparationTests: XCTestCase {
    func draft() -> PreparationDraft {
        var d = PreparationDraft()
        d.corners = PerformancePlan.area.corners.map { Optional($0) }
        return d
    }
    func testOutsideEndpointsAndInternalLimits() throws {
        var d = draft()
        try d.addRoutePoint(Point3(-1,0,-2))
        XCTAssertThrowsError(try d.addRoutePoint(Point3(-1,0,-3)))
        try d.addRoutePoint(Point3(2,0,-2))
        try d.addRoutePoint(Point3(13,0,-2), asDestination: true)
        XCTAssertTrue(d.routeErrors.isEmpty)
        XCTAssertEqual(try d.stageRoute().version, 2)
        let decoded = try JSONDecoder().decode(StageRoute.self, from: JSONEncoder().encode(d.stageRoute()))
        XCTAssertTrue(decoded.conflicts(boundaryMargin: 0.01, obstacleClearance: 0.35).isEmpty)
        XCTAssertFalse(RouteGuide(route: decoded, settings: GuideSettings()).ready(position: decoded.points[0], headingDegrees: 0, trackingValid: true))
    }
    func testWorldLocationsSurviveBoundaryEditAndHeightIsRechecked() throws {
        var d = draft()
        try d.addRoutePoint(Point3(-1,0,-2)); try d.addRoutePoint(Point3(1,0,-2))
        try d.addRoutePoint(Point3(13,0,-2), asDestination: true)
        d.checkpoint = Point3(5,0,-4)
        let before = d.route
        d.corners = PerformancePlan.area.corners.map { Point3($0.x+2,$0.y,$0.z) }
        XCTAssertEqual(before, d.route)
        XCTAssertEqual(d.checkpoint, Point3(5,0,-4))
        XCTAssertFalse(d.routeErrors.isEmpty)
        d.corners = PerformancePlan.area.corners.map { Point3($0.x,0.4,$0.z) }
        XCTAssertFalse(d.checkpointErrors.isEmpty)
        XCTAssertThrowsError(try d.stageRoute())
    }
    func testEntrySegmentCannotCrossPlatform() throws {
        var d = draft()
        try d.addRoutePoint(Point3(-1,0,-2)); try d.addRoutePoint(Point3(5,0,-2))
        try d.addRoutePoint(Point3(13,0,-2), asDestination: true)
        d.objects = [WorldObstacle(name: "단상", kind: .platform, vertices: [Point3(1,0,-1),Point3(2,0,-1),Point3(2,0,-3),Point3(1,0,-3)])]
        XCTAssertFalse(d.routeErrors.isEmpty)
    }
    func testSixPointLimitUndoAndWrongFloor() throws {
        var d = draft()
        try d.addRoutePoint(Point3(-1,0,-2))
        XCTAssertThrowsError(try d.addRoutePoint(Point3(2,1,-2)))
        for x in 2...5 { try d.addRoutePoint(Point3(Double(x),0,-2)) }
        XCTAssertThrowsError(try d.addRoutePoint(Point3(6,0,-2)))
        try d.addRoutePoint(Point3(13,0,-2), asDestination: true)
        XCTAssertThrowsError(try d.addRoutePoint(Point3(14,0,-2), asDestination: true))
        d.removeLastRoutePoint()
        XCTAssertFalse(d.routeFinished)
        XCTAssertEqual(d.route.count, 5)
        try d.addRoutePoint(Point3(14,0,-2), asDestination: true)
    }
    func testPlannerFinishAndPersistence() async throws {
        var p = PerformancePlan()
        try p.append(FloorPoint(-1,2)); try p.append(FloorPoint(3,2))
        XCTAssertThrowsError(try p.finishRoute())
        try p.append(FloorPoint(13,2))
        XCTAssertThrowsError(try p.append(FloorPoint(4,3)))
        try p.finishRoute()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PerformancePlanStore(root: root)
        try await store.save(p)
        let loaded = try await store.list()
        XCTAssertEqual(loaded, [p])
        p.name = "수정한 동선"; try await store.save(p)
        let updated = try await store.list()
        XCTAssertEqual(updated.count, 1); XCTAssertEqual(updated.first?.name, p.name)
        p.undoPoint(); XCTAssertFalse(p.finished); XCTAssertEqual(p.points.count, 2)
    }
    func testPlannerObjectConflictAfterFinishing() throws {
        var p = PerformancePlan()
        try p.append(FloorPoint(-1,2)); try p.append(FloorPoint(3,2)); try p.append(FloorPoint(13,2)); try p.finishRoute()
        try p.addObject(at: FloorPoint(6,2), platform: true)
        XCTAssertThrowsError(try p.validate())
        try p.moveObject(p.objects[0].id, to: FloorPoint(6,5))
        XCTAssertNoThrow(try p.validate())
        XCTAssertThrowsError(try p.moveObject(p.objects[0].id, to: FloorPoint(-1,5)))
    }
    func testPinsRoundTripAndNoDuplicates() throws {
        let area = PerformancePlan.area
        let frame = try StageFrame(origin: area.world(FloorPoint(0,0)), front: area.world(FloorPoint(0,-1)))
        let m = ScanManifest(id: UUID(), name: "무대", frame: frame, checkpoint: Point3(4,0,-4), worldMapHash: "", meshHash: "", meshCount: 1, vertexCount: 3, device: "", appVersion: "")
        var pins = LibraryPins(); pins.toggle(m.id)
        let restored = try JSONDecoder().decode(LibraryPins.self, from: JSONEncoder().encode(pins))
        XCTAssertEqual(restored.groups([m]).pinned.count, 1)
        XCTAssertTrue(restored.groups([m]).recent.isEmpty)
        pins.toggle(m.id)
        XCTAssertEqual(pins.groups([m]).recent.count, 1)
    }
}
