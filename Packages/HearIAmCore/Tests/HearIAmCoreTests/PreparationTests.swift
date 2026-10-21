import XCTest
@testable import HearIAmCore

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
    func testEntrySegmentCannotCrossObstacle() throws {
        var d = draft()
        try d.addRoutePoint(Point3(-1,0,-2)); try d.addRoutePoint(Point3(5,0,-2))
        try d.addRoutePoint(Point3(13,0,-2), asDestination: true)
        d.objects = [WorldObstacle(name: "상자", kind: .box, vertices: [Point3(1,0,-1),Point3(2,0,-1),Point3(2,0,-3),Point3(1,0,-3)])]
        XCTAssertFalse(d.routeErrors.isEmpty)
        // A platform in the same place is walked onto, so the route is fine (decided 10/17).
        d.objects = [WorldObstacle(name: "단상", kind: .platform, vertices: [Point3(1,0,-1),Point3(2,0,-1),Point3(2,0,-3),Point3(1,0,-3)])]
        XCTAssertTrue(d.routeErrors.isEmpty)
    }
    func testTwentyPointsAfterStartLimitUndoAndWrongFloor() throws {
        var d = draft()
        try d.addRoutePoint(Point3(-1,0,-2))
        XCTAssertThrowsError(try d.addRoutePoint(Point3(2,1,-2)))
        for i in 0..<19 { try d.addRoutePoint(Point3(2+Double(i)*0.3,0,-2)) }
        XCTAssertThrowsError(try d.addRoutePoint(Point3(6,0,-2)))
        try d.addRoutePoint(Point3(13,0,-2), asDestination: true)
        XCTAssertThrowsError(try d.addRoutePoint(Point3(14,0,-2), asDestination: true))
        d.removeLastRoutePoint()
        XCTAssertFalse(d.routeFinished)
        XCTAssertEqual(d.route.count, 20)
        try d.addRoutePoint(Point3(14,0,-2), asDestination: true)
    }
    func testPlannerFinishAndPersistence() async throws {
        var p = PerformancePlan()
        try p.append(FloorPoint(-1,2))
        XCTAssertThrowsError(try p.append(FloorPoint(-1,3)))
        try p.append(FloorPoint(3,2))
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
        try p.addObject(at: FloorPoint(6,2), platform: false)
        XCTAssertThrowsError(try p.validate())
        try p.moveObject(p.objects[0].id, to: FloorPoint(6,5))
        XCTAssertNoThrow(try p.validate())
        XCTAssertThrowsError(try p.moveObject(p.objects[0].id, to: FloorPoint(-1,5)))
    }
    func testPreparationArchiveRetainsOutsideEndpointsAndPolicy() async throws {
        var d = draft()
        try d.addRoutePoint(Point3(-1,0,-2)); try d.addRoutePoint(Point3(2,0,-2))
        try d.addRoutePoint(Point3(13,0,-2), asDestination: true)
        d.checkpoint = Point3(6,0,-4)
        let route = try d.stageRoute()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScanStore(root: root)
        let mesh = MeshSnapshot(id: UUID(), transform: [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],
            vertices: [Point3(0,0,0),Point3(1,0,0),Point3(0,0,-1)], indices: [0,1,2])
        var settings = GuideSettings()
        settings.boundaryMargin = PreparationDraft.boundaryMargin
        settings.obstacleClearance = PreparationDraft.obstacleClearance
        let id = UUID()
        _ = try await store.save(id: id, name: "출입 포함 무대", frame: StageFrame(origin: Point3(0,0,0), front: Point3(0,0,1)),
            checkpoint: d.checkpoint!, worldMap: Data([1,2,3]), meshes: [mesh], device: "test", appVersion: "1", route: route, settings: settings)
        let loaded = try await store.load(id)
        XCTAssertEqual(loaded.manifest.route, route)
        XCTAssertEqual(loaded.manifest.settings, settings)
        XCTAssertEqual(loaded.manifest.version, 2)
    }
    func testDeletingPlanOnlyRemovesSelectedFileAndIsRepeatable() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=PerformancePlanStore(root:root)
        var first=PerformancePlan()
        try first.append(.init(-1,2));try first.append(.init(3,2));try first.append(.init(13,2));try first.finishRoute()
        var second=first;second.id=UUID();second.name="유지할 동선"
        try await store.save(first);try await store.save(second)
        try await store.delete(first.id);try await store.delete(first.id)
        let remaining=try await PerformancePlanStore(root:root).list()
        XCTAssertEqual(remaining.map(\.id),[second.id])
    }
    func testDeletingScanRemovesBundleButPreservesOtherScanAndPins() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root)
        let frame=try StageFrame(origin:.init(0,0,0),front:.init(0,0,1))
        let mesh=MeshSnapshot(id:UUID(),transform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],
            vertices:[.init(0,0,0),.init(1,0,0),.init(0,0,-1)],indices:[0,1,2])
        let deletedID=UUID(), retainedID=UUID()
        for id in [deletedID,retainedID] {
            _=try await store.save(id:id,name:"테스트",frame:frame,checkpoint:.init(3,0,-2),worldMap:Data([1]),meshes:[mesh],device:"test",appVersion:"1")
        }
        var pins=LibraryPins();pins.toggle(deletedID);pins.toggle(retainedID)
        try await store.delete(deletedID);try await store.delete(deletedID);pins.remove(deletedID)
        let remaining=try await ScanStore(root:root).list()
        XCTAssertEqual(remaining.map(\.id),[retainedID])
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent(deletedID.uuidString).path))
        let reloadedPins=try JSONDecoder().decode(LibraryPins.self,from:JSONEncoder().encode(pins))
        XCTAssertEqual(reloadedPins.ids,[retainedID])
        let retained=try await store.load(retainedID)
        XCTAssertEqual(retained.meshes,[mesh])
    }
    func testScanRenamePersistsWithoutChangingAssetsPinsOrSaveOrder() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root)
        var d=draft()
        try d.addRoutePoint(.init(-1,0,-2));try d.addRoutePoint(.init(2,0,-2))
        try d.addRoutePoint(.init(13,0,-2),asDestination:true)
        let route=try d.stageRoute()
        let frame=try StageFrame(origin:.init(0,0,0),front:.init(0,0,1))
        let mesh=MeshSnapshot(id:UUID(),transform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],
            vertices:[.init(0,0,0),.init(1,0,0),.init(0,0,-1)],indices:[0,1,2])
        let id=UUID()
        for scanID in [id,UUID()] {
            _=try await store.save(id:scanID,name:"원래 무대",frame:frame,checkpoint:.init(6,0,-4),
                worldMap:Data([1,2,3]),meshes:[mesh],device:"test",appVersion:"1",route:route)
        }
        let directory=root.appendingPathComponent(id.uuidString)
        let manifestURL=directory.appendingPathComponent("manifest.json")
        var expected=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:manifestURL)) as? [String:Any])
        let assets=try ["worldmap.bin","mesh.json"].map {try Data(contentsOf:directory.appendingPathComponent($0))}
        let original=try await store.list()
        var pins=LibraryPins();pins.toggle(id)
        let originalGroups=pins.groups(original)

        let renamed=try await store.rename(id,to:"  새 공연장 · 리허설 동선 \n")
        XCTAssertEqual(renamed.name,"새 공연장 · 리허설 동선")
        expected["name"]=renamed.name
        let actual=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:manifestURL)) as? [String:Any])
        XCTAssertEqual(actual as NSDictionary,expected as NSDictionary)
        XCTAssertEqual(try ["worldmap.bin","mesh.json"].map {try Data(contentsOf:directory.appendingPathComponent($0))},assets)
        let reopened=ScanStore(root:root)
        let reloaded=try await reopened.load(id)
        XCTAssertEqual(reloaded.manifest.name,renamed.name)
        XCTAssertEqual(reloaded.manifest.route,route)
        let updated=try await reopened.list()
        XCTAssertEqual(updated.map(\.id),original.map(\.id))
        XCTAssertEqual(pins.groups(updated).pinned.map(\.id),originalGroups.pinned.map(\.id))
        XCTAssertEqual(pins.groups(updated).recent.map(\.id),originalGroups.recent.map(\.id))

        let savedData=try Data(contentsOf:manifestURL)
        for invalid in ["", " \n\t ", String(repeating:"가",count:81)] {
            do {_=try await store.rename(id,to:invalid);XCTFail("Invalid name accepted")}
            catch {}
            XCTAssertEqual(try Data(contentsOf:manifestURL),savedData)
        }
        let missingID=UUID()
        do {_=try await store.rename(missingID,to:"없는 무대");XCTFail("Missing scan recreated")}
        catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent(missingID.uuidString).path))
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
    func testApplyPerformancePlanProjectsRouteAndObstaclesToStageArea() throws {
        var plan = PerformancePlan()
        plan.name = "리허설 동선"
        try plan.append(FloorPoint(-1, 2))
        try plan.append(FloorPoint(6, 4))
        try plan.append(FloorPoint(13, 6))
        try plan.addObject(at: FloorPoint(3, 6), platform: true)
        try plan.finishRoute()

        var d = PreparationDraft()
        // 6m × 4m stage (half scale of 12×8 schematic plan)
        d.corners = [Point3(0, 0, 0), Point3(6, 0, 0), Point3(6, 0, -4), Point3(0, 0, -4)]
        try d.applyPlan(plan)

        XCTAssertTrue(d.routeFinished)
        XCTAssertEqual(d.route.count, 3)
        XCTAssertEqual(d.objects.count, 1)
        let route = try d.stageRoute()
        XCTAssertEqual(route.points[0].x, -0.5, accuracy: 1e-6)
        XCTAssertEqual(route.points[0].y, 1.0, accuracy: 1e-6)
        XCTAssertEqual(route.points[1].x, 3.0, accuracy: 1e-6)
        XCTAssertEqual(route.points[1].y, 2.0, accuracy: 1e-6)
        XCTAssertEqual(route.points[2].x, 6.5, accuracy: 1e-6)
        XCTAssertEqual(route.points[2].y, 3.0, accuracy: 1e-6)
    }
    /// 10/19: an interior point keeps 0.15 m inside the stage edge; the start and destination may stand outside.
    func testInteriorPointsKeepClearOfTheStageEdge() throws {
        var d = draft()
        try d.addRoutePoint(Point3(0.05,0,-2))
        XCTAssertEqual(d.edgeIssue(adding: Point3(0.1,0,-3)), "내부 지점은 무대 가장자리에서 15cm 이상 안쪽에 찍어주세요")
        XCTAssertThrowsError(try d.addRoutePoint(Point3(0.1,0,-3)))
        XCTAssertThrowsError(try d.addRoutePoint(Point3(5,0,-7.9)))
        try d.addRoutePoint(Point3(0.2,0,-3))
        XCTAssertNil(d.edgeIssue(adding: Point3(11.95,0,-3), asDestination: true))
        try d.addRoutePoint(Point3(11.95,0,-3), asDestination: true)
        XCTAssertTrue(d.routeErrors.isEmpty)
    }
}
