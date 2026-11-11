import XCTest
@testable import HearIAmCore

/// Saving a scan's route edited on the performance's route editor (#179).
final class ScanRouteEditTests: XCTestCase {
    private func photo(at index: Int?) -> ScanPhoto {
        ScanPhoto(capturedAt:Date(timeIntervalSince1970:1_700_000_000),frameTimestamp:1,cameraTransform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],
                  pixelWidth:10,pixelHeight:10,imageHash:String(repeating:"a",count:64),thumbnailHash:String(repeating:"b",count:64),
                  routePointIndex:index)
    }

    func testPhotosFollowTheirPointsAndLoseARemovedOne() {
        // Scanned 0 1 2 3; edited: a point added after 0, scanned 2 removed → 0 nil 1 3.
        let photos=[photo(at:1),photo(at:2),photo(at:3),photo(at:nil)]
        let moved=ScanPhoto.following(photos,origins:[0,nil,1,3])
        XCTAssertEqual(moved.map(\.routePointIndex),[2,nil,3,nil])
        XCTAssertEqual(moved.map(\.id),photos.map(\.id))
        XCTAssertEqual(moved[0].imageHash,photos[0].imageHash)
    }

    func testConflictsNameThePointsAsOnScreen() throws {
        let route=try StageRoute(area:PerformancePlan.area,points:[.init(2,2),.init(0.1,4),.init(6,2)],obstacles:[])
        let lines=route.guidanceConflicts(GuideSettings())
        XCTAssertEqual(lines,["P1 지점이 무대 가장자리에 너무 가까워요."])
    }

    func testReplaceRouteRefusesARouteGuidanceWouldRefuse() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root), id=UUID()
        let r=try StageRoute(area:PerformancePlan.area,points:[.init(2,2),.init(4,2),.init(6,2)],obstacles:[])
        let mesh=MeshSnapshot(id:UUID(),transform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],vertices:[.init(0,0,0),.init(1,0,0),.init(0,0,1)],indices:[0,1,2])
        _=try await store.save(id:id,name:"가장자리",frame:StageFrame(origin:r.area.world(.init(0,0)),front:r.area.world(.init(0,-1))),
                              checkpoint:r.area.world(.init(1,1)),worldMap:Data([1]),meshes:[mesh],device:"test",appVersion:"test",route:r)
        let edge=try StageRoute(area:r.area,points:[.init(2,2),.init(0.1,4),.init(6,2)],obstacles:[])
        do {_=try await store.replaceRoute(id,with:edge);XCTFail("saved a route guidance refuses")}
        catch {XCTAssertTrue(error.localizedDescription.contains("P1"))}
        let loaded=try await store.load(id)
        XCTAssertEqual(loaded.manifest.route?.points,r.points)
    }

    func testTheEditorsSourceIndexIsNotSaved() throws {
        var settings=PerformancePlanPointSettings(name:"앞",holdSeconds:3);settings.sourceIndex=2
        let decoded=try JSONDecoder().decode(PerformancePlanPointSettings.self,from:JSONEncoder().encode(settings))
        XCTAssertNil(decoded.sourceIndex);XCTAssertEqual(decoded.name,"앞");XCTAssertEqual(decoded.holdSeconds,3)
    }
}
