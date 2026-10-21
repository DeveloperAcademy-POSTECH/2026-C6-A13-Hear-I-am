import XCTest
@testable import HearIAmCore

final class SpaceStorageTests: XCTestCase {
    let identity: [Float]=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    func testLegacyAssignmentPreservesMapGeometryPhotosAndDate() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root)
        let scan=try await save(store:store,route:route())
        let original=try await store.load(scan.id)
        let linked=try await store.assign(scan.id,venueID:"daegu-practice",roomID:"daegu-practice-large")
        let loaded=try await store.load(scan.id)
        XCTAssertEqual(linked.date,scan.date);XCTAssertEqual(linked.route,scan.route)
        XCTAssertEqual(linked.photos,scan.photos);XCTAssertEqual(loaded.worldMap,original.worldMap)
        XCTAssertEqual(loaded.meshes,original.meshes);XCTAssertEqual(linked.meshHash,scan.meshHash)
        XCTAssertNil(scan.space);XCTAssertEqual(linked.space?.roomID,"daegu-practice-large")
    }
    func testBaseAndTwoPerformancesStayIndependentAcrossReloadAndDeletion() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root)
        let base=try await save(store:store,route:nil,context:.init(venueID:"v",roomID:"r",purpose:.base,roomArea:PerformancePlan.area,checkpointNote:"문 옆 고정 표식"))
        let bytes=try Data(contentsOf:root.appendingPathComponent(base.id.uuidString).appendingPathComponent("manifest.json"))
        let context=ScanSpaceContext(venueID:"v",roomID:"r",baseScanID:base.id,baseMeshHash:base.meshHash,roomArea:PerformancePlan.area)
        let a=try await save(store:store,route:route(),context:context)
        let b=try await save(store:store,route:route(),context:context)
        _=try await store.rename(a.id,to:"A 공연")
        do {_=try await store.assign(a.id,venueID:"v",roomID:"other");XCTFail("Cannot change the physical room of a base-derived scan")} catch {}
        try await store.delete(a.id)
        let reloaded=ScanStore(root:root)
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent(base.id.uuidString).appendingPathComponent("manifest.json")),bytes)
        let bReloaded=try await reloaded.load(b.id)
        XCTAssertEqual(bReloaded.manifest.space?.baseScanID,base.id)
        // Each performance owns a full snapshot, so it remains usable even if a base archive is removed.
        try await store.delete(base.id)
        let preserved=try await reloaded.load(b.id)
        XCTAssertEqual(preserved.manifest.route,b.route)
    }
    func testInvalidBaseAndUnknownMeshLayerCannotPublish() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root)
        do {_=try await save(store:store,route:nil,context:.init(venueID:"v",roomID:"r",purpose:.base));XCTFail()} catch {}
        do {_=try await save(store:store,route:route(),context:.init(venueID:"v",roomID:"r",purpose:.base,roomArea:PerformancePlan.area,checkpointNote:"C"));XCTFail()} catch {}
        let all=try await store.list();XCTAssertTrue(all.isEmpty)
    }
    private func route() throws -> StageRoute {
        try StageRoute(area:PerformancePlan.area,points:[.init(1,2),.init(3,2),.init(5,2)],obstacles:[])
    }
    private func save(store: ScanStore,route: StageRoute?,context: ScanSpaceContext? = nil) async throws -> ScanManifest {
        let area=PerformancePlan.area
        return try await store.save(id:UUID(),name:"공간",frame:StageFrame(origin:area.world(.init(0,0)),front:area.world(.init(0,-1))),checkpoint:area.world(.init(2,1)),worldMap:Data([1,2,3]),meshes:[MeshSnapshot(id:UUID(),transform:identity,vertices:area.corners,indices:[0,1,2,0,2,3])],device:"test",appVersion:"1",route:route,space:context)
    }
}
