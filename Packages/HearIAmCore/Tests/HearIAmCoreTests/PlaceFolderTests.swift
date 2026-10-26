import XCTest
@testable import HearIAmCore

final class PlaceFolderTests: XCTestCase {
    func temporaryRoot() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("places-test-"+UUID().uuidString) }
    func place(_ name: String = "연습실 A") -> PlaceEntry {
        .init(name:name,address:"대구 남구 명덕로 42",kind:.rehearsal,folders:[.init(name:"대연습실"),.init(name:"소연습실")])
    }
    func scan(_ name: String = "Look at me") throws -> ScanManifest {
        let area=PerformancePlan.area
        return ScanManifest(id:UUID(),name:name,frame:try StageFrame(origin:area.world(.init(0,0)),front:area.world(.init(0,1))),checkpoint:area.world(.init(1,1)),worldMapHash:"map",meshHash:"mesh",meshCount:1,vertexCount:3,device:"test",appVersion:"test")
    }
    func testExistingScansAreUnassignedWithoutMigration() async throws {
        let root=temporaryRoot();defer {try? FileManager.default.removeItem(at:root)}
        let index=try await PlaceFolderStore(root:root).load(), old=try scan()
        XCTAssertTrue(index.places.isEmpty);XCTAssertNil(index.destination(for:old.id))
        XCTAssertEqual(index.path(for:old.id),["장소 미지정"])
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.path))
    }
    func testRoundTripMoveAndDeleteNeverTouchScanBundle() async throws {
        let root=temporaryRoot();defer {try? FileManager.default.removeItem(at:root)}
        let store=PlaceFolderStore(root:root.appendingPathComponent("Places")), p=place(), id=UUID()
        let original=root.appendingPathComponent("Scans").appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at:original,withIntermediateDirectories:true)
        let files=["manifest.json":Data("original metadata".utf8),"mesh.json":Data([1,2,3]),"worldmap.bin":Data([4,5,6])]
        for (name,data) in files {try data.write(to:original.appendingPathComponent(name))}
        _ = try await store.upsert(p,photo:Data([1,2,3]))
        let destination=PlaceDestination(placeID:p.id,folderID:p.folders[0].id)
        _ = try await store.assign([id],to:destination)
        var index=try await PlaceFolderStore(root:root.appendingPathComponent("Places")).load()
        XCTAssertEqual(index.destination(for:id),destination)
        index=try await store.assign([id],to:.init(placeID:p.id))
        XCTAssertEqual(index.path(for:id),[p.name])
        index=try await store.deletePlace(p.id)
        XCTAssertNil(index.destination(for:id))
        for (name,data) in files {XCTAssertEqual(try Data(contentsOf:original.appendingPathComponent(name)),data)}
    }
    func testRemovingOneFolderOnlyReleasesItsPerformances() async throws {
        let root=temporaryRoot();defer {try? FileManager.default.removeItem(at:root)}
        let store=PlaceFolderStore(root:root);var p=place()
        _ = try await store.upsert(p,photo:Data([1]))
        let a=UUID(),b=UUID(),c=UUID()
        _ = try await store.assign([a],to:.init(placeID:p.id,folderID:p.folders[0].id))
        _ = try await store.assign([b],to:.init(placeID:p.id,folderID:p.folders[1].id))
        _ = try await store.assign([c],to:.init(placeID:p.id))
        p.folders.removeFirst()
        let result=try await store.upsert(p)
        XCTAssertNil(result.destination(for:a));XCTAssertNotNil(result.destination(for:b));XCTAssertNotNil(result.destination(for:c))
    }
    func testInvalidMoveLeavesSavedAssignmentsUnchanged() async throws {
        let root=temporaryRoot();defer {try? FileManager.default.removeItem(at:root)}
        let store=PlaceFolderStore(root:root),p=place(),id=UUID()
        _ = try await store.upsert(p,photo:Data([1]))
        let before=try await store.assign([id],to:.init(placeID:p.id))
        do {_ = try await store.assign([id],to:.init(placeID:p.id,folderID:UUID()));XCTFail("invalid destination accepted")} catch {}
        let after=try await store.load();XCTAssertEqual(before,after)
    }
    func testCorruptOrFutureIndexIsNotOverwritten() async throws {
        for data in [Data("broken".utf8),Data("{\"version\":9,\"places\":[],\"assignments\":[],\"favoriteScans\":[]}".utf8)] {
            let root=temporaryRoot();defer {try? FileManager.default.removeItem(at:root)}
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            let url=root.appendingPathComponent("places.json");try data.write(to:url)
            let store=PlaceFolderStore(root:root)
            do {_ = try await store.upsert(place(),photo:Data([1]));XCTFail("corrupt file replaced")} catch {}
            XCTAssertEqual(try Data(contentsOf:url),data)
        }
    }
    func testPhotoReplacementAndMissingPhotoRecovery() async throws {
        let root=temporaryRoot();defer {try? FileManager.default.removeItem(at:root)}
        let store=PlaceFolderStore(root:root),p=place()
        var state=try await store.upsert(p,photo:Data([1,2]))
        let old=state.places[0].photoID
        let initial=try await store.photo(old);XCTAssertEqual(initial,Data([1,2]))
        state=try await store.upsert(state.places[0],photo:Data([3,4]))
        XCTAssertNotEqual(old,state.places[0].photoID)
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("photos/\(old.uuidString).jpg").path))
        let newURL=root.appendingPathComponent("photos/\(state.places[0].photoID.uuidString).jpg")
        try FileManager.default.removeItem(at:newURL)
        let loaded=try await store.load();XCTAssertEqual(loaded.places.count,1)
        state=try await store.upsert(state.places[0],photo:Data([5]))
        XCTAssertEqual(state.places.count,1)
    }
    func testNewPlaceRequiresPhotoAndInvalidNamesFail() async throws {
        let root=temporaryRoot();defer {try? FileManager.default.removeItem(at:root)}
        let store=PlaceFolderStore(root:root)
        do {_ = try await store.upsert(place());XCTFail("photo missing")} catch {}
        var p=place();p.name="  ";XCTAssertThrowsError(try p.validate())
        p=place();p.address="";XCTAssertThrowsError(try p.validate())
        p=place();p.folders[1].name=" 대연습실 ";XCTAssertThrowsError(try p.validate())
        p=place();p.folders[1].id=p.folders[0].id;XCTAssertThrowsError(try p.validate())
    }
    func testSameNamePerformancesRemainSeparateWithTheirPaths() throws {
        let a=try scan(),b=try scan(),unassigned=try scan("기타 공연")
        let p=place("대구공연예술연습공간"),q=PlaceEntry(name:"효자아트홀",address:"경북 포항시",kind:.theater)
        var index=PlaceFolderIndex();index.places=[p,q]
        index.assignments[a.id] = .init(placeID:p.id,folderID:p.folders[0].id)
        index.assignments[b.id] = .init(placeID:q.id)
        let found=PlaceSearch.search("  LOOK   at me ",index:index,scans:[a,b,unassigned])
        XCTAssertEqual(Set(found.performances.map(\.id)),[a.id,b.id]);XCTAssertTrue(found.matchesPerformanceName)
        XCTAssertEqual(index.path(for:a.id),[p.name,"대연습실"])
        XCTAssertEqual(index.path(for:b.id),[q.name])
    }
    func testVenueAddressFolderAndUnassignedSearch() throws {
        let a=try scan(),b=try scan("미지정 공연"),p=place("대구공연예술연습공간")
        var index=PlaceFolderIndex();index.places=[p];index.assignments[a.id] = .init(placeID:p.id,folderID:p.folders[0].id)
        for query in ["대구","남구","대연습실","대구공연예술연습공간".decomposedStringWithCanonicalMapping] {
            let result=PlaceSearch.search(query,index:index,scans:[a,b])
            XCTAssertEqual(result.places.map(\.id),[p.id]);XCTAssertEqual(result.performances.map(\.id),[a.id])
        }
        XCTAssertEqual(PlaceSearch.search("장소 미지정",index:index,scans:[a,b]).performances.map(\.id),[b.id])
        XCTAssertTrue(PlaceSearch.search("없음",index:index,scans:[a,b]).performances.isEmpty)
        XCTAssertTrue(PlaceSearch.search("  ",index:index,scans:[a,b]).places.isEmpty)
    }
    func testReceiptDoesNotClassifyCancelledOrMultipleSessions() throws {
        let old=try scan(), start=Date(), receipt=PlaceScanReceipt(scans:[old],startedAt:start)
        XCTAssertNil(try receipt.newScan(in:[old]))
        let new=try scan();XCTAssertEqual(try receipt.newScan(in:[old,new]),new.id)
        XCTAssertThrowsError(try receipt.newScan(in:[old,new,scan()]))
        XCTAssertNil(try PlaceScanReceipt(scans:[],startedAt:Date().addingTimeInterval(10)).newScan(in:[old]))
    }
    func testIndependentFavoritesAndRecentOrderingPersist() async throws {
        let root=temporaryRoot();defer {try? FileManager.default.removeItem(at:root)}
        let store=PlaceFolderStore(root:root),p=place("나"),q=place("가"),id=UUID()
        _ = try await store.upsert(p,photo:Data([1]));_ = try await store.upsert(q,photo:Data([2]))
        _ = try await store.togglePlaceFavorite(p.id);_ = try await store.togglePerformanceFavorite(id)
        let state=try await store.visit(p.id,at:Date().addingTimeInterval(10))
        XCTAssertEqual(PlaceSort.recent.sorted(state.places).first?.id,p.id)
        XCTAssertEqual(PlaceSort.name.sorted(state.places).first?.id,q.id)
        XCTAssertTrue(state.places.first {$0.id==p.id}!.favorite);XCTAssertTrue(state.favoriteScans.contains(id))
        let reopened=try await store.load();XCTAssertEqual(reopened,state)
    }
}
