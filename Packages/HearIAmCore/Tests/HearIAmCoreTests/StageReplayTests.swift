import XCTest
@testable import HearIAmCore

final class StageReplayTests: XCTestCase {
    let identity: [Float]=[1,0,0,0, 0,1,0,0, 0,0,1,0, 2,1,3,1]
    func object(appearance: ObjectAppearance? = nil) throws -> StageObstacle {
        try StageObstacle(name:"기물",kind:.other,vertices:[.init(1,1),.init(3,1),.init(3,2),.init(1,2)],height:0.8,appearance:appearance)
    }
    func source(_ root: URL, objectID: UUID? = nil) throws -> ScanPhotoSource {
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let image=Data([1,2,3]), thumbnail=Data([4,5])
        let photo=ScanPhoto(capturedAt:Date(),frameTimestamp:10,cameraTransform:identity,pixelWidth:1600,pixelHeight:900,
                            imageHash:ScanStore.hash(image),thumbnailHash:ScanStore.hash(thumbnail),objectID:objectID)
        let full=root.appendingPathComponent(photo.id.uuidString+".jpg"), thumb=root.appendingPathComponent(photo.id.uuidString+"-thumb.jpg")
        try image.write(to:full); try thumbnail.write(to:thumb)
        return ScanPhotoSource(photo:photo,imageURL:full,thumbnailURL:thumb)
    }
    func save(_ store: ScanStore, photos: [ScanPhotoSource] = []) async throws -> ScanManifest {
        try await store.save(id:UUID(),name:"무대",frame:StageFrame(origin:.init(0,0,0),front:.init(0,0,-1)),
                             checkpoint:.init(2,0,0),worldMap:Data([1]),
                             meshes:[MeshSnapshot(id:UUID(),transform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],
                                                  vertices:[.init(0,0,0),.init(1,0,0),.init(0,0,1)],indices:[0,1,2])],
                             device:"test",appVersion:"1",photos:photos)
    }
    func testOldObjectDecodesAndAppearanceDoesNotChangeGuidance() throws {
        let before=try object()
        var dict=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(before)) as? [String:Any])
        dict.removeValue(forKey:"appearance")
        let old=try JSONDecoder().decode(StageObstacle.self,from:JSONSerialization.data(withJSONObject:dict))
        XCTAssertNil(old.appearance)
        let after=try object(appearance:.init(model:.chair,headingDegrees:90))
        XCTAssertEqual(before.vertices,after.vertices); XCTAssertEqual(before.blocksPath,after.blocksPath)
        XCTAssertEqual(before.distance(to:.init(0,0)),after.distance(to:.init(0,0)))
        XCTAssertEqual(after,try JSONDecoder().decode(StageObstacle.self,from:JSONEncoder().encode(after)))
    }
    func testPlacementRespectsHeadingAndMeasuredHeight() throws {
        let a=ObjectPlacement(try object())
        let b=ObjectPlacement(try object(appearance:.init(model:.table,headingDegrees:90)))
        XCTAssertEqual(a.width,2,accuracy:0.00001); XCTAssertEqual(a.depth,1,accuracy:0.00001)
        XCTAssertEqual(b.width,1,accuracy:0.00001); XCTAssertEqual(b.depth,2,accuracy:0.00001)
        XCTAssertEqual(a.center,.init(2,1.5)); XCTAssertEqual(b.height,0.8); XCTAssertTrue(b.measuredHeight)
        var missing=try object(); missing.height=nil; missing.appearance = .init(model:.chair)
        XCTAssertEqual(ObjectPlacement(missing).height,0.85); XCTAssertFalse(ObjectPlacement(missing).measuredHeight)
    }
    func testWorldProjectionPreservesAppearance() throws {
        let world=WorldObstacle(name:"의자",kind:.other,vertices:[.init(1,0,-1),.init(2,0,-1),.init(2,0,-2)],height:0.9,
                                appearance:.init(model:.chair,headingDegrees:180))
        let stage=try world.projected(in:PerformancePlan.area)
        XCTAssertEqual(stage.appearance,world.appearance); XCTAssertEqual(stage.height,0.9)
    }
    func testUnknownModelFallsBackAndInvalidHeadingRejected() throws {
        let model=try JSONDecoder().decode(ObjectAppearance.Model.self,from:Data("\"future-asset\"".utf8))
        XCTAssertEqual(model,.generic)
        XCTAssertThrowsError(try ObjectAppearance(headingDegrees:.nan).validate())
    }
    func testPhotoPoseValidation() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let good=try source(root).photo
        XCTAssertNoThrow(try good.validate()); XCTAssertEqual(good.position,.init(2,1,3)); XCTAssertEqual(good.forward,.init(0,0,-1))
        for transform in [[],Array(repeating:Float(0),count:16)] {
            let bad=ScanPhoto(capturedAt:Date(),frameTimestamp:0,cameraTransform:transform,pixelWidth:100,pixelHeight:100,
                              imageHash:good.imageHash,thumbnailHash:good.thumbnailHash)
            XCTAssertThrowsError(try bad.validate())
        }
    }
    func testPhotoRoundTripRenameDeleteAndLazyRead() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root.appendingPathComponent("scans")), photo=try source(root)
        let saved=try await save(store,photos:[photo])
        let loaded=try await store.load(saved.id)
        XCTAssertEqual(loaded.manifest.photos,[photo.photo])
        let data=try await store.photoData(scanID:saved.id,photoID:photo.photo.id,thumbnail:false)
        XCTAssertEqual(data,Data([1,2,3]))
        let renamed=try await store.rename(saved.id,to:"새 이름")
        XCTAssertEqual(renamed.photos,saved.photos)
        try await store.delete(saved.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("scans/\(saved.id)").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:photo.imageURL.path))
    }
    func testMissingAndCorruptPhotoStillAllowScanToOpen() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root.appendingPathComponent("scans")), photo=try source(root)
        let saved=try await save(store,photos:[photo])
        let url=root.appendingPathComponent("scans/\(saved.id)/photos/\(photo.photo.id).jpg")
        try Data([9]).write(to:url)
        do {_=try await store.photoData(scanID:saved.id,photoID:photo.photo.id,thumbnail:false); XCTFail()} catch {}
        try FileManager.default.removeItem(at:url)
        do {_=try await store.photoData(scanID:saved.id,photoID:photo.photo.id,thumbnail:false); XCTFail()} catch {}
        let loaded=try await store.load(saved.id); XCTAssertEqual(loaded.meshes.count,1)
    }
    func testFailedPhotoSavePublishesNothingAndRetainsDraft() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let scanRoot=root.appendingPathComponent("scans"), store=ScanStore(root:scanRoot)
        let photo=try source(root)
        try FileManager.default.removeItem(at:photo.thumbnailURL)
        do {_=try await save(store,photos:[photo]); XCTFail()} catch {}
        let list=try await store.list(); XCTAssertTrue(list.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:scanRoot.path).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath:photo.imageURL.path))
    }
    func testLegacyManifestWithoutPhotos() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root), saved=try await save(store)
        let url=root.appendingPathComponent("\(saved.id)/manifest.json")
        var dict=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:url)) as? [String:Any])
        dict.removeValue(forKey:"photos"); try JSONSerialization.data(withJSONObject:dict).write(to:url)
        let loaded=try await store.load(saved.id); XCTAssertTrue(loaded.manifest.photos.isEmpty)
    }
    func testDuplicateAndDanglingPhotoLinksRejected() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root.appendingPathComponent("scans")), photo=try source(root)
        do {_=try await save(store,photos:[photo,photo]); XCTFail()} catch {}
        let dangling=try source(root,objectID:UUID())
        do {_=try await save(store,photos:[dangling]); XCTFail()} catch {}
        let list=try await store.list(); XCTAssertTrue(list.isEmpty)
    }
}
