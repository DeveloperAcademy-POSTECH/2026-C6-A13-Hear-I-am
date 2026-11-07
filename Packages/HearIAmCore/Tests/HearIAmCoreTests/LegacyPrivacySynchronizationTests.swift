import XCTest
@testable import HearIAmCore

final class LegacyPrivacySynchronizationTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let places: PlaceFolderStore
        let catalog: PerformanceCatalogStore
        let first: ScanManifest
        let second: ScanManifest
        let source: PlaceEntry
        let empty: PlaceEntry
        let originalIndex: PlaceFolderIndex
        let initial: PerformanceCatalog
    }

    private func scan(_ name: String) throws -> ScanManifest {
        let area=PerformancePlan.area
        return ScanManifest(id:UUID(),name:name,
                            frame:try StageFrame(origin:area.world(.init(0,0)),front:area.world(.init(0,1))),
                            checkpoint:area.world(.init(1,1)),worldMapHash:"map",meshHash:"mesh",meshCount:1,
                            vertexCount:3,device:"test",appVersion:"test")
    }
    private func fixture(shared: Bool = false) async throws -> Fixture {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("legacy-privacy-"+UUID().uuidString)
        let places=PlaceFolderStore(root:root.appendingPathComponent("PlaceFolders"))
        let catalog=PerformanceCatalogStore(root:root.appendingPathComponent("Performances"))
        let first=try scan("공연 A"), second=try scan(shared ? "공연 B" : "공연 A")
        let source=PlaceEntry(name:"원래 공연장",address:"원래 주소",kind:.theater,folders:[.init(name:"연습실")])
        let empty=PlaceEntry(name:"비어 있는 독립 장소",address:"보존할 주소",kind:.rehearsal)
        _ = try await places.upsert(source,photo:Data([1,2,3]))
        _ = try await places.upsert(empty,photo:Data([4,5,6]))
        _ = try await places.assign([first.id,second.id],to:.init(placeID:source.id,folderID:source.folders[0].id))
        let index=try await places.togglePerformanceFavorite(first.id)
        let initial=try await catalog.migrateIfNeeded(scans:[first,second],plans:[],places:index)
        return Fixture(root:root,places:places,catalog:catalog,first:first,second:second,
                       source:index.places.first {$0.id==source.id}!,empty:index.places.first {$0.id==empty.id}!,
                       originalIndex:index,initial:initial)
    }

    func testExclusiveRenameUpdatesBothCopiesAndVoicePathWithoutChangingPhotoOrAddress() async throws {
        let f=try await fixture();defer {try? FileManager.default.removeItem(at:f.root)}
        let performance=f.initial.folder(for:f.first.id)!,venue=f.initial.venue(for:f.first.id)!
        let updated=try await f.catalog.upsertVenue(.init(id:venue.id,name:"새 공연장"),in:performance.id)
        let source=try await f.places.reconcileLegacySnapshot(updated)
        XCTAssertEqual(updated.assignments[f.first.id]?.legacyPath,["새 공연장","연습실"])
        XCTAssertEqual(updated.legacyPlaces?.places.first {$0.id==f.source.id}?.name,"새 공연장")
        XCTAssertEqual(source.places.first {$0.id==f.source.id}?.name,"새 공연장")
        XCTAssertEqual(source.places.first {$0.id==f.source.id}?.address,f.source.address)
        let photo=try await f.places.photo(f.source.photoID)
        XCTAssertEqual(photo,Data([1,2,3]));XCTAssertTrue(source.places.contains(f.empty))
    }

    func testSharedRenameDetachesOnlyChangedPerformanceAndPreservesOtherOwner() async throws {
        let f=try await fixture(shared:true);defer {try? FileManager.default.removeItem(at:f.root)}
        let performance=f.initial.folder(for:f.first.id)!,venue=f.initial.venue(for:f.first.id)!
        let updated=try await f.catalog.upsertVenue(.init(id:venue.id,name:"A 공연 전용 이름"),in:performance.id)
        let source=try await f.places.reconcileLegacySnapshot(updated)
        XCTAssertEqual(updated.assignments[f.first.id]?.legacyPath,[])
        XCTAssertNil(source.assignments[f.first.id])
        XCTAssertEqual(updated.assignments[f.second.id]?.legacyPath,[f.source.name,"연습실"])
        XCTAssertEqual(source.assignments[f.second.id],f.originalIndex.assignments[f.second.id])
        XCTAssertTrue(source.places.contains(f.source))
        XCTAssertEqual(updated.legacySynchronization?.venuePlaceIDs[venue.id],[])
    }

    func testVenueDeletionClearsOldSearchReferencesButKeepsArchivedPhotosAndEmptyPlaces() async throws {
        let f=try await fixture();defer {try? FileManager.default.removeItem(at:f.root)}
        let performance=f.initial.folder(for:f.first.id)!,venue=f.initial.venue(for:f.first.id)!
        let updated=try await f.catalog.deleteVenue(venue.id,in:performance.id)
        let source=try await f.places.reconcileLegacySnapshot(updated)
        for id in [f.first.id,f.second.id] {
            XCTAssertNil(updated.assignments[id]?.venueID)
            XCTAssertEqual(updated.assignments[id]?.legacyPath,[])
            XCTAssertNil(updated.legacyPlaces?.assignments[id]);XCTAssertNil(source.assignments[id])
        }
        XCTAssertEqual(source.places,f.originalIndex.places)
        XCTAssertTrue(source.favoriteScans.contains(f.first.id))
        let photo=try await f.places.photo(f.source.photoID)
        XCTAssertEqual(photo,Data([1,2,3]))
    }

    func testPerformanceDeletionDoesNotDeleteOtherPerformanceReferencesOrUserBundles() async throws {
        let f=try await fixture(shared:true);defer {try? FileManager.default.removeItem(at:f.root)}
        let bundle=f.root.appendingPathComponent("Scans/retained.bin")
        try FileManager.default.createDirectory(at:bundle.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data([7,8,9]).write(to:bundle)
        let updated=try await f.catalog.deletePerformance(f.initial.folder(for:f.first.id)!.id)
        let source=try await f.places.reconcileLegacySnapshot(updated)
        XCTAssertNil(updated.assignments[f.first.id]);XCTAssertNil(source.assignments[f.first.id])
        XCTAssertEqual(updated.assignments[f.second.id],f.initial.assignments[f.second.id])
        XCTAssertEqual(source.assignments[f.second.id],f.originalIndex.assignments[f.second.id])
        XCTAssertEqual(source.places,f.originalIndex.places)
        XCTAssertEqual(try Data(contentsOf:bundle),Data([7,8,9]))
    }

    func testMoveDropsFormerAliasesOnlyWhenClassificationActuallyChanges() async throws {
        let f=try await fixture();defer {try? FileManager.default.removeItem(at:f.root)}
        let folder=f.initial.folder(for:f.first.id)!,venue=f.initial.venue(for:f.first.id)!
        let unchanged=try await f.catalog.assign([f.first.id],to:folder.id,venueID:venue.id)
        XCTAssertEqual(unchanged.assignments[f.first.id]?.legacyPath,[f.source.name,"연습실"])
        let changed=try await f.catalog.assign([f.first.id],to:folder.id)
        let source=try await f.places.reconcileLegacySnapshot(changed)
        XCTAssertEqual(changed.assignments[f.first.id]?.legacyPath,[])
        XCTAssertNil(source.assignments[f.first.id])
        XCTAssertNotNil(source.assignments[f.second.id])
        XCTAssertTrue(source.places.contains(f.source))
    }

    func testDeletedScanReferencesAndFavoritesAreRemovedAndRefreshIsIdempotent() async throws {
        let f=try await fixture();defer {try? FileManager.default.removeItem(at:f.root)}
        let removed=try await f.catalog.removeScanReferences(f.first.id)
        XCTAssertNil(removed.assignments[f.first.id])
        XCTAssertFalse(removed.legacyPlaces!.favoriteScans.contains(f.first.id))
        let caughtUp=try await f.catalog.reconcileScanReferences(validScanIDs:[])
        let source=try await f.places.reconcileLegacySnapshot(caughtUp)
        XCTAssertTrue(caughtUp.assignments.isEmpty);XCTAssertTrue(source.assignments.isEmpty)
        XCTAssertTrue(source.favoriteScans.isEmpty);XCTAssertEqual(source.places,f.originalIndex.places)
        let again=try await f.catalog.reconcileScanReferences(validScanIDs:[])
        XCTAssertEqual(again,caughtUp)
        let repeated=try await f.places.reconcileLegacySnapshot(again)
        XCTAssertEqual(repeated,source)
    }

    func testStaleSnapshotCannotResurrectReferencesAfterReopeningSourceStore() async throws {
        let f=try await fixture();defer {try? FileManager.default.removeItem(at:f.root)}
        let independent=PlaceEntry(name:"별도 저장 장소",address:"새 주소",kind:.rehearsal)
        let scanID=UUID()
        _ = try await f.places.upsert(independent,photo:Data([9]))
        _ = try await f.places.assign([scanID],to:.init(placeID:independent.id))
        let removed=try await f.catalog.removeScanReferences(f.first.id)
        let applied=try await f.places.reconcileLegacySnapshot(removed)
        let reopened=PlaceFolderStore(root:f.root.appendingPathComponent("PlaceFolders"))
        let stale=try await reopened.reconcileLegacySnapshot(f.initial)
        XCTAssertEqual(stale,applied)
        XCTAssertNil(stale.assignments[f.first.id])
        XCTAssertEqual(stale.assignments[scanID]?.placeID,independent.id)
        XCTAssertTrue(stale.places.contains {$0.id==independent.id})
    }

    func testCorruptSourceIsPreservedAndPendingCatalogChangeCanRetry() async throws {
        let f=try await fixture();defer {try? FileManager.default.removeItem(at:f.root)}
        let url=f.root.appendingPathComponent("PlaceFolders/places.json")
        let original=try Data(contentsOf:url), damaged=Data("invalid original".utf8)
        try damaged.write(to:url)
        let pending=try await f.catalog.removeScanReferences(f.first.id)
        do {_ = try await f.places.reconcileLegacySnapshot(pending);XCTFail("corrupt source overwritten")} catch {}
        XCTAssertEqual(try Data(contentsOf:url),damaged)
        try original.write(to:url)
        let latest=try await f.catalog.load()
        let retried=try await f.places.reconcileLegacySnapshot(latest)
        XCTAssertNil(retried.assignments[f.first.id]);XCTAssertTrue(retried.places.contains(f.source))
    }

    func testLegacyCatalogDecodesWithoutNewMetadataAndMissingOriginalIsNotRecreated() async throws {
        let f=try await fixture();defer {try? FileManager.default.removeItem(at:f.root)}
        let catalogURL=f.root.appendingPathComponent("Performances/performances.json")
        var json=try JSONSerialization.jsonObject(with:Data(contentsOf:catalogURL)) as! [String:Any]
        json.removeValue(forKey:"legacySynchronization")
        try JSONSerialization.data(withJSONObject:json).write(to:catalogURL)
        let loaded=try await f.catalog.load()
        XCTAssertNil(loaded.legacySynchronization)
        let normalized=try await f.catalog.reconcileScanReferences(validScanIDs:[f.first.id,f.second.id])
        XCTAssertNotNil(normalized.legacySynchronization)
        let original=f.root.appendingPathComponent("PlaceFolders/places.json")
        try FileManager.default.removeItem(at:original)
        _ = try await f.places.reconcileLegacySnapshot(normalized)
        XCTAssertFalse(FileManager.default.fileExists(atPath:original.path))
    }

    func testOldDeletedAndMovedVenueAliasesAreDetachedWithoutGuessingSourceRename() async throws {
        for hasVenue in [false,true] {
            let f=try await fixture();defer {try? FileManager.default.removeItem(at:f.root)}
            var old=f.initial
            old.legacySynchronization=nil
            let performanceIndex=old.performances.firstIndex {$0.id==old.folder(for:f.first.id)!.id}!
            if hasVenue {
                old.performances[performanceIndex].venues[0].name="이미 옮긴 다른 공연장"
            } else {
                old.performances[performanceIndex].venues=[]
                old.assignments[f.first.id]?.venueID=nil
                old.assignments[f.second.id]?.venueID=nil
            }
            try JSONEncoder().encode(old).write(to:f.root.appendingPathComponent("Performances/performances.json"))
            let repaired=try await f.catalog.reconcileScanReferences(validScanIDs:[f.first.id,f.second.id])
            XCTAssertEqual(repaired.assignments[f.first.id]?.legacyPath,[])
            XCTAssertNil(repaired.legacyPlaces?.assignments[f.first.id])
            XCTAssertTrue(repaired.legacySynchronization!.venuePlaceIDs.isEmpty)
            let source=try await f.places.reconcileLegacySnapshot(repaired)
            XCTAssertNil(source.assignments[f.first.id])
            XCTAssertTrue(source.places.contains(f.source))
            if hasVenue {
                let venue=repaired.venue(for:f.first.id)!
                let renamed=try await f.catalog.upsertVenue(.init(id:venue.id,name:"또 다른 이름"),in:repaired.folder(for:f.first.id)!.id)
                let reconciled=try await f.places.reconcileLegacySnapshot(renamed)
                XCTAssertTrue(reconciled.places.contains(f.source))
            }
        }
    }

    func testReimportAfterCatalogRemovalContinuesSourceRevisionWithoutBlockingRefresh() async throws {
        let f=try await fixture();defer {try? FileManager.default.removeItem(at:f.root)}
        let source=try await f.places.reconcileLegacySnapshot(f.initial)
        try FileManager.default.removeItem(at:f.root.appendingPathComponent("Performances/performances.json"))
        let imported=try await f.catalog.migrateIfNeeded(scans:[f.first,f.second],plans:[],places:source)
        XCTAssertEqual(imported.legacySynchronization?.id,source.performanceSynchronizationID)
        XCTAssertGreaterThan(imported.legacySynchronization!.revision,source.performanceSynchronizationRevision!)
        let applied=try await f.places.reconcileLegacySnapshot(imported)
        XCTAssertEqual(applied.performanceSynchronizationRevision,imported.legacySynchronization?.revision)
        XCTAssertEqual(applied.places,source.places)
    }
}
