import XCTest
@testable import HearIAmCore

final class PerformanceCatalogTests: XCTestCase {
    private func root() -> URL {FileManager.default.temporaryDirectory.appendingPathComponent("performance-test-"+UUID().uuidString)}
    private func scan(_ name: String) throws -> ScanManifest {
        let area=PerformancePlan.area
        return ScanManifest(id:UUID(),name:name,frame:try StageFrame(origin:area.world(.init(0,0)),front:area.world(.init(0,1))),checkpoint:area.world(.init(1,1)),worldMapHash:"map",meshHash:"mesh",meshCount:1,vertexCount:3,device:"test",appVersion:"test")
    }
    private func plan(_ name: String = "Lion King") throws -> PerformancePlan {
        var value=PerformancePlan();value.name=name
        try value.append(.init(1,1));try value.append(.init(4,3));try value.append(.init(8,3));try value.finishRoute()
        return value
    }
    func testMigrationGroupsPerformancesRetainsEveryPlanAndOriginalPlaceMetadata() async throws {
        let directory=root();defer {try? FileManager.default.removeItem(at:directory)}
        let a=try scan("Lion King"),b=try scan("lion   king"),c=try scan("다른 공연")
        let venue=PlaceEntry(name:"대구 공연장",address:"주소",kind:.theater,folders:[.init(name:"소극장"),.init(name:"비어 있는 폴더")])
        var places=PlaceFolderIndex();places.places=[venue]
        places.assignments[a.id] = .init(placeID:venue.id,folderID:venue.folders[0].id)
        places.assignments[b.id] = .init(placeID:venue.id)
        places.favoriteScans=[a.id]
        let first=try plan(),second=try plan(),standalone=try plan("독립 사전 동선")
        let store=PerformanceCatalogStore(root:directory)
        let migrated=try await store.migrateIfNeeded(scans:[a,b,c],plans:[first,second,standalone],places:places)
        XCTAssertEqual(migrated.folder(for:a.id)?.id,migrated.folder(for:b.id)?.id)
        XCTAssertEqual(migrated.venue(for:a.id)?.id,migrated.venue(for:b.id)?.id)
        XCTAssertEqual(migrated.assignments[a.id]?.legacyPath,[venue.name,"소극장"])
        XCTAssertEqual(migrated.legacyPlaces,places)
        XCTAssertEqual(Set(migrated.performances.compactMap(\.defaultPlanID)),Set([first.id,second.id,standalone.id]))
        XCTAssertEqual(migrated.assignments.count,3)
        let again=try await store.migrateIfNeeded(scans:[],plans:[],places:PlaceFolderIndex())
        XCTAssertEqual(again,migrated)
    }
    func testTagAndFolderDeletionPreserveSourceBundlesAndDoNotResurrectOnMigration() async throws {
        let directory=root();defer {try? FileManager.default.removeItem(at:directory)}
        let original=directory.appendingPathComponent("Scans/worldmap.bin"), bytes=Data([1,4,9,16])
        try FileManager.default.createDirectory(at:original.deletingLastPathComponent(),withIntermediateDirectories:true)
        try bytes.write(to:original)
        let source=try scan("Lion King"), store=PerformanceCatalogStore(root:directory.appendingPathComponent("catalog"))
        var catalog=try await store.migrateIfNeeded(scans:[source],plans:[],places:PlaceFolderIndex())
        let folder=catalog.performances[0],tag=PerformanceVenueTag(name:"공연장 A")
        _ = try await store.upsertVenue(tag,in:folder.id)
        _ = try await store.assign([source.id],to:folder.id,venueID:tag.id)
        catalog=try await store.deleteVenue(tag.id,in:folder.id)
        XCTAssertEqual(catalog.folder(for:source.id)?.id,folder.id)
        XCTAssertNil(catalog.venue(for:source.id))
        catalog=try await store.deletePerformance(folder.id)
        XCTAssertNil(catalog.assignments[source.id])
        let again=try await store.migrateIfNeeded(scans:[source],plans:[],places:PlaceFolderIndex())
        XCTAssertEqual(again,catalog);XCTAssertEqual(try Data(contentsOf:original),bytes)
    }
    func testDuplicateNamesAndInvalidBatchMoveLeavePersistedCatalogUnchanged() async throws {
        let directory=root();defer {try? FileManager.default.removeItem(at:directory)}
        let store=PerformanceCatalogStore(root:directory)
        _ = try await store.migrateIfNeeded(scans:[],plans:[],places:PlaceFolderIndex())
        let a=PerformanceFolder(name:"Lion King"),b=PerformanceFolder(name:"다른 공연"),tag=PerformanceVenueTag(name:"공연장 A")
        _ = try await store.upsert(a);_ = try await store.upsert(b);_ = try await store.upsertVenue(tag,in:a.id)
        let ids=[UUID(),UUID()]
        let before=try await store.assign(ids,to:a.id,venueID:tag.id)
        do {_ = try await store.upsert(.init(name:" LION   KING "));XCTFail("duplicate performance accepted")} catch {}
        do {_ = try await store.upsertVenue(.init(name:" 공연장 A "),in:a.id);XCTFail("duplicate tag accepted")} catch {}
        do {_ = try await store.assign(ids,to:b.id,venueID:tag.id);XCTFail("foreign tag accepted")} catch {}
        let after=try await store.load();XCTAssertEqual(before,after)
        let moved=try await store.assign(ids,to:b.id)
        XCTAssertTrue(ids.allSatisfy {moved.assignments[$0]?.performanceID==b.id})
    }
    func testCorruptCatalogIsNotOverwrittenByMigrationOrCreate() async throws {
        let directory=root();defer {try? FileManager.default.removeItem(at:directory)}
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let file=directory.appendingPathComponent("performances.json"),data=Data("broken catalog".utf8)
        try data.write(to:file)
        let store=PerformanceCatalogStore(root:directory)
        do {_ = try await store.migrateIfNeeded(scans:[],plans:[],places:PlaceFolderIndex());XCTFail("corrupt catalog replaced")} catch {}
        do {_ = try await store.upsert(.init(name:"새 공연"));XCTFail("corrupt catalog replaced")} catch {}
        XCTAssertEqual(try Data(contentsOf:file),data)
    }
}
