import XCTest
@testable import HearIAmCore

final class CheckpointAlignmentTests: XCTestCase {
    let saved=[Point3(2,0,3),Point3(6,0,3)]
    func observed(yaw: Double = 0, dx: Double = 0.1, dz: Double = -0.1) -> [Point3] {
        let angle=yaw * .pi/180
        return saved.map { p in
            let x=p.x-4, z=p.z-3
            return Point3(4+dx+cos(angle)*x+sin(angle)*z,p.y,3+dz-sin(angle)*x+cos(angle)*z)
        }
    }
    func testTranslationAndRotationAlignBothPointsWithoutChangingHeightOrScale() throws {
        for yaw in [-8.0,0,8] {
            let points=observed(yaw:yaw)
            let t=try CheckpointAlignment(saved:saved,observed:points)
            XCTAssertEqual(t.yawDegrees,yaw,accuracy:1e-9)
            for i in saved.indices { XCTAssertLessThan(t.apply(saved[i]).distance(to:points[i]),1e-9) }
            let p=Point3(10,1.7,-5), q=Point3(-1,0.6,4)
            XCTAssertLessThan(t.inverse(t.apply(p)).distance(to:p),1e-9)
            XCTAssertEqual(t.apply(p).y,p.y)
            XCTAssertEqual(t.apply(p).distance(to:t.apply(q)),p.distance(to:q),accuracy:1e-9)
        }
    }
    func testInverseHeadingUsesRotationWithoutTranslation() throws {
        let t=try CheckpointAlignment(saved:saved,observed:observed(yaw:8))
        let frame=try StageFrame(origin:Point3(0,0,0),front:Point3(0,0,1))
        let angle=8.0 * .pi/180
        let currentForward=Point3(sin(angle),0,cos(angle))
        XCTAssertEqual(try XCTUnwrap(frame.heading(cameraForward:t.inverseDirection(currentForward))),0,accuracy:1e-9)
    }
    func testUnequalLengthsLeaveSymmetricResidualWithoutScaling() throws {
        let t=try CheckpointAlignment(saved:saved,observed:[Point3(1.95,0,3),Point3(6.05,0,3)])
        XCTAssertEqual(t.lengthDifference,0.1,accuracy:1e-9)
        XCTAssertEqual(t.residual,0.05,accuracy:1e-9)
        XCTAssertEqual(t.apply(saved[0]).distance(to:t.apply(saved[1])),4,accuracy:1e-9)
    }
    func testRejectsSwappedRepeatedShortMissingAndInvalidPoints() {
        XCTAssertThrowsError(try CheckpointAlignment(saved:saved,observed:saved.reversed()))
        XCTAssertThrowsError(try CheckpointAlignment(saved:saved,observed:[saved[0],saved[0]]))
        XCTAssertThrowsError(try CheckpointAlignment(saved:[Point3(0,0,0),Point3(0.9,0,0)],observed:saved))
        XCTAssertThrowsError(try CheckpointAlignment(saved:saved,observed:[saved[0]]))
        XCTAssertThrowsError(try CheckpointAlignment(saved:saved,observed:[Point3(.nan,0,0),saved[1]]))
    }
    func testRejectsLargeTranslationRotationLengthAndHeightErrors() {
        XCTAssertThrowsError(try CheckpointAlignment(saved:saved,observed:observed(dx:0.51,dz:0)))
        XCTAssertThrowsError(try CheckpointAlignment(saved:saved,observed:observed(yaw:11)))
        XCTAssertThrowsError(try CheckpointAlignment(saved:saved,observed:[Point3(1.9,0,3),Point3(6.1,0,3)]))
        XCTAssertThrowsError(try CheckpointAlignment(saved:saved,observed:saved.map {Point3($0.x,0.16,$0.z)}))
        // Each component is within its limit but their combined 3D residual is not.
        XCTAssertThrowsError(try CheckpointAlignment(saved:saved,observed:[Point3(1.93,0.14,3),Point3(6.07,0.14,3)]))
    }
    func testDraftRequiresTwoSeparatedValidFloorPoints() {
        var draft=PreparationDraft()
        draft.corners=PerformancePlan.area.corners.map(Optional.some)
        draft.checkpoint=PerformancePlan.area.world(.init(3,3))
        XCTAssertFalse(draft.checkpointErrors.isEmpty)
        draft.secondCheckpoint=draft.checkpoint
        XCTAssertFalse(draft.checkpointErrors.isEmpty)
        draft.secondCheckpoint=PerformancePlan.area.world(.init(6,3))
        XCTAssertTrue(draft.checkpointErrors.isEmpty)
        draft.secondCheckpoint=Point3(6,0.5,-3)
        XCTAssertFalse(draft.checkpointErrors.isEmpty)
    }
    func manifest(second: Point3? = nil) throws -> ScanManifest {
        let area=PerformancePlan.area
        let route=try StageRoute(area:area,points:[.init(2,2),.init(4,2),.init(6,2)],obstacles:[])
        return ScanManifest(id:UUID(),name:"무대",frame:try StageFrame(origin:area.world(.init(0,0)),front:area.world(.init(0,-1))),checkpoint:area.world(.init(3,4)),worldMapHash:"map",meshHash:"mesh",meshCount:1,vertexCount:3,device:"test",appVersion:"test",route:route,secondCheckpoint:second)
    }
    func testLegacyAndTwoPointManifestRoundTripsAndMissingSecondPointFails() throws {
        let legacy=try manifest()
        let old=try JSONDecoder().decode(ScanManifest.self,from:JSONEncoder().encode(legacy))
        XCTAssertNoThrow(try old.validate()); XCTAssertFalse(old.supportsAlignment)
        let current=try manifest(second:PerformancePlan.area.world(.init(7,4)))
        let decoded=try JSONDecoder().decode(ScanManifest.self,from:JSONEncoder().encode(current))
        XCTAssertNoThrow(try decoded.validate()); XCTAssertTrue(decoded.supportsAlignment)
        XCTAssertEqual(decoded.version,3); XCTAssertEqual(decoded.secondCheckpoint,current.secondCheckpoint)
        var broken=legacy; broken.version=3
        XCTAssertThrowsError(try broken.validate())
        var wrongVersion=current; wrongVersion.version=2
        XCTAssertThrowsError(try wrongVersion.validate())
    }
    func testStoreRetainsBothLandmarksAndOriginalMap() async throws {
        let m=try manifest(second:PerformancePlan.area.world(.init(7,4)))
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root), map=Data([1,2,3])
        let mesh=MeshSnapshot(id:UUID(),transform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],vertices:[Point3(0,0,0),Point3(1,0,0),Point3(0,0,1)],indices:[0,1,2])
        _=try await store.save(id:m.id,name:m.name,frame:m.frame,checkpoint:m.checkpoint,worldMap:map,meshes:[mesh],device:"test",appVersion:"test",route:m.route,secondCheckpoint:m.secondCheckpoint)
        let loaded=try await store.load(m.id)
        XCTAssertEqual(loaded.worldMap,map)
        XCTAssertEqual(loaded.manifest.checkpoint,m.checkpoint)
        XCTAssertEqual(loaded.manifest.secondCheckpoint,m.secondCheckpoint)
        XCTAssertTrue(loaded.manifest.supportsAlignment)
    }
}
