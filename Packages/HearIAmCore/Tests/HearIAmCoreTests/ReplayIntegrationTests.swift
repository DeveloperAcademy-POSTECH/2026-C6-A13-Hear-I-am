import XCTest
@testable import HearIAmCore

/// Latest develop permits 21 points; photo links and completed replay must support the final target too.
final class ReplayIntegrationTests: XCTestCase {
    func testTwentyOnePointPhotoRetryAndFinalTargetReplayRoundTrip() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let points=(0..<21).map {FloorPoint(1+Double($0)*0.4,3)}
        let route=try StageRoute(area:PerformancePlan.area,points:points,obstacles:[],allowsOutsideEndpoints:true,
            pointHeights:Array(repeating:0,count:21))
        let image=Data([1,2,3]),thumbnail=Data([4,5])
        let imageURL=root.appendingPathComponent("photo.jpg"),thumbnailURL=root.appendingPathComponent("thumb.jpg")
        try image.write(to:imageURL)
        let transform: [Float]=[1,0,0,0,0,1,0,0,0,0,1,0,2,1,3,1]
        let photo=ScanPhoto(capturedAt:Date(),frameTimestamp:10,cameraTransform:transform,pixelWidth:1600,pixelHeight:900,
            imageHash:ScanStore.hash(image),thumbnailHash:ScanStore.hash(thumbnail),routePointIndex:20)
        let source=ScanPhotoSource(photo:photo,imageURL:imageURL,thumbnailURL:thumbnailURL)
        let store=ScanStore(root:root.appendingPathComponent("scans")),id=UUID()
        func save() async throws -> ScanManifest {
            try await store.save(id:id,name:"21점 동선",frame:StageFrame(origin:route.area.world(.init(0,0)),front:route.area.world(.init(0,-1))),
                checkpoint:route.area.world(.init(2,1)),worldMap:Data([1]),
                meshes:[MeshSnapshot(id:UUID(),transform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],
                    vertices:[.init(0,0,0),.init(1,0,0),.init(0,0,1)],indices:[0,1,2])],
                device:"test",appVersion:"1",route:route,photos:[source])
        }
        do {_=try await save();XCTFail("Incomplete photo must not publish an archive")} catch {}
        let failedList=try await store.list()
        XCTAssertTrue(failedList.isEmpty)
        XCTAssertEqual(try Data(contentsOf:imageURL),image,"Photo draft survives failed save")
        try thumbnail.write(to:thumbnailURL)
        let saved=try await save(),loaded=try await store.load(saved.id)
        XCTAssertEqual(loaded.manifest.route,route)
        XCTAssertEqual(loaded.manifest.photos.first?.routePointIndex,20)
        let readImage=try await store.photoData(scanID:id,photoID:photo.id,thumbnail:false)
        XCTAssertEqual(readImage,image)

        let replay=GuidanceReplay(duration:0.2,samples:[
            .init(time:0,position:points[19],heading:0,targetIndex:20,status:.guiding),
            .init(time:0.2,position:points[20],heading:0,targetIndex:20,status:.guiding)])
        let start=Date(timeIntervalSince1970:1000)
        let record=GuidanceRecord(version:2,id:UUID(),stageID:id,stageName:saved.name,route:route,
            startedAt:start,completedAt:start.addingTimeInterval(0.2),finishedAt:start.addingTimeInterval(1),
            activeSeconds:0.2,replay:replay)
        try record.validate()
        let records=GuidanceRecordStore(root:root.appendingPathComponent("records"))
        try await records.save(record)
        let recordList=try await records.list()
        let restored=try XCTUnwrap(recordList.first)
        XCTAssertEqual(restored,record)
        XCTAssertEqual(restored.reachedPointCount,20)
        XCTAssertEqual(restored.replay?.pose(at:0.2)?.targetIndex,20)
        XCTAssertEqual(restored.replay?.pose(at:0.2)?.position,points[20])
    }
}
