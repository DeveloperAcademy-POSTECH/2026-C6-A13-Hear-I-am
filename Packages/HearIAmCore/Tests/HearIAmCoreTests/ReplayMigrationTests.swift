import XCTest
@testable import HearIAmCore

/// Integration boundaries between develop's route rules and #49's display/photo data.
final class ReplayMigrationTests: XCTestCase {
    private func chair(appearance: ObjectAppearance? = .init(model:.chair,headingDegrees:90)) throws -> StageObstacle {
        try StageObstacle(name:"의자",kind:.platform,passage:.passable,
            vertices:[.init(2,2),.init(4,2),.init(4,4),.init(2,4)],height:0.4,
            entryEdges:[3],exitEdges:[1],facingEdge:1,appearance:appearance)
    }
    private func route(appearance: ObjectAppearance? = .init(model:.chair,headingDegrees:90)) throws -> StageRoute {
        var draft=PreparationDraft()
        draft.corners=PerformancePlan.area.corners.map(Optional.some)
        let area=try XCTUnwrap(draft.area), object=try chair(appearance:appearance)
        draft.objects=[WorldObstacle(id:object.id,name:object.name,kind:object.kind,
            vertices:object.vertices.map(area.world),height:object.height,
            entryEdges:object.entryEdges,exitEdges:object.exitEdges,facingEdge:object.facingEdge,appearance:object.appearance)]
        try draft.addRoutePoint(area.world(.init(1,3)))
        var top=area.world(.init(3,3)); top.y += 0.4
        try draft.addRoutePoint(top)
        try draft.addRoutePoint(area.world(.init(5,3)),asDestination:true)
        return try draft.stageRoute()
    }
    private func save(_ store: ScanStore, route: StageRoute, photos: [ScanPhotoSource] = []) async throws -> ScanManifest {
        try await store.save(id:UUID(),name:"합쳐진 다시보기",frame:StageFrame(origin:route.area.world(.init(0,0)),front:route.area.world(.init(0,-1))),
            checkpoint:route.area.world(.init(6,2)),worldMap:Data([1]),
            meshes:[MeshSnapshot(id:UUID(),transform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],
                vertices:[.init(0,0,0),.init(1,0,0),.init(0,0,1)],indices:[0,1,2])],
            device:"test",appVersion:"1",route:route,photos:photos)
    }
    private func assertGuidanceEdges(_ object: StageObstacle, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(object.entryEdges,[3],file:file,line:line)
        XCTAssertEqual(object.exitEdges,[1],file:file,line:line)
        XCTAssertEqual(object.facingEdge,1,file:file,line:line)
        XCTAssertFalse(object.blocksTravel(from:.init(1,3),to:.init(5,3),clearance:0.1),file:file,line:line)
        XCTAssertFalse(object.blocksTravel(from:.init(5,3),to:.init(1,3),clearance:0.1),file:file,line:line)
    }
    func testRaisedRouteWithPhotosPreservesAppearanceAndGuidance() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let route=try route(), object=try XCTUnwrap(route.obstacles.first)
        let image=Data([1,2,3]), thumb=Data([4,5])
        let photo=ScanPhoto(capturedAt:Date(),frameTimestamp:10,cameraTransform:[1,0,0,0,0,1,0,0,0,0,1,0,3,1,-3,1],
            pixelWidth:1600,pixelHeight:900,imageHash:ScanStore.hash(image),thumbnailHash:ScanStore.hash(thumb),
            objectID:object.id,routePointIndex:1)
        let fullURL=root.appendingPathComponent("full.jpg"), thumbURL=root.appendingPathComponent("thumb.jpg")
        try image.write(to:fullURL); try thumb.write(to:thumbURL)
        let source=ScanPhotoSource(photo:photo,imageURL:fullURL,thumbnailURL:thumbURL)
        let store=ScanStore(root:root.appendingPathComponent("scans"))
        let saved=try await save(store,route:route,photos:[source])
        let loaded=try await store.load(saved.id), restored=try XCTUnwrap(loaded.manifest.route)
        XCTAssertEqual(restored,route)
        XCTAssertEqual(restored.pointHeights,[0,0.4,0])
        XCTAssertEqual(restored.obstacles[0].appearance,object.appearance)
        assertGuidanceEdges(restored.obstacles[0])
        XCTAssertEqual(loaded.manifest.photos,[photo])
        let restoredImage=try await store.photoData(scanID:saved.id,photoID:photo.id,thumbnail:false)
        XCTAssertEqual(restoredImage,image)
        let renamed=try await store.rename(saved.id,to:"이름 변경")
        XCTAssertEqual(renamed.route,route); XCTAssertEqual(renamed.photos,[photo])
    }
    func testDevelopArchiveWithoutReplayFieldsKeepsHeightsAndEdgeRestrictions() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root), original=try route(appearance:nil)
        let saved=try await save(store,route:original)
        let url=root.appendingPathComponent(saved.id.uuidString).appendingPathComponent("manifest.json")
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        json.removeValue(forKey:"photos")
        try JSONSerialization.data(withJSONObject:json).write(to:url)
        let loaded=try await store.load(saved.id), restored=try XCTUnwrap(loaded.manifest.route)
        XCTAssertEqual(restored,original)
        XCTAssertEqual(restored.pointHeights,[0,0.4,0])
        XCTAssertNil(restored.obstacles[0].appearance)
        assertGuidanceEdges(restored.obstacles[0])
        XCTAssertTrue(loaded.manifest.photos.isEmpty)
    }
    func testPlanImportPreservesBothDisplayAndAccessMetadataAcrossStageTransform() throws {
        var plan=PerformancePlan()
        plan.objects=[try chair()]
        for point in [FloorPoint(1,3),.init(3,3),.init(5,3)] {try plan.append(point)}
        try plan.finishRoute()
        let stored=try JSONDecoder().decode(PerformancePlan.self,from:JSONEncoder().encode(plan))
        var draft=PreparationDraft()
        draft.corners=[Point3(10,1,20),Point3(10,1,26),Point3(14,1,26),Point3(14,1,20)].map(Optional.some)
        try draft.applyPlan(stored)
        let area=try XCTUnwrap(draft.area), imported=try XCTUnwrap(draft.objects.first)
        let projected=try imported.projected(in:area), original=plan.objects[0]
        XCTAssertEqual(projected.id,original.id)
        XCTAssertEqual(projected.appearance,original.appearance)
        XCTAssertEqual(projected.height,original.height)
        XCTAssertEqual(projected.entryEdges,original.entryEdges)
        XCTAssertEqual(projected.exitEdges,original.exitEdges)
        XCTAssertEqual(projected.facingEdge,original.facingEdge)
        XCTAssertEqual(projected.vertices,[.init(1,1),.init(2,1),.init(2,2),.init(1,2)])
        XCTAssertFalse(projected.blocksTravel(from:.init(0.5,1.5),to:.init(2.5,1.5),clearance:0.05))
        XCTAssertFalse(projected.blocksTravel(from:.init(2.5,1.5),to:.init(0.5,1.5),clearance:0.05))
        XCTAssertTrue(draft.routeErrors.isEmpty)
    }
    func testAppearanceAndAccessMetadataAreValidatedIndependently() throws {
        var object=try chair()
        object.appearance = .init(model:.chair,headingDegrees:.nan)
        XCTAssertThrowsError(try object.validate())
        object.appearance = .init(model:.table,headingDegrees:180)
        object.facingEdge=4
        XCTAssertThrowsError(try object.validate())
        object.facingEdge=1
        XCTAssertNoThrow(try object.validate())
        assertGuidanceEdges(object)
    }
}
