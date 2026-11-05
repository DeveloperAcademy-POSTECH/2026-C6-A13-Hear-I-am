import XCTest
@testable import HearIAmCore

final class PerformanceScenesTests: XCTestCase {
    private func directory() -> URL {FileManager.default.temporaryDirectory.appendingPathComponent("reference-scenes-"+UUID().uuidString)}

    func testLegacySinglePlanAndVenueIDsSurviveDecodeAndRoundTrip() throws {
        let planID=UUID(),date=Date(timeIntervalSince1970:1_700_000_000)
        let folder=PerformanceFolder(name:"Lion King",defaultPlanID:planID,venues:[.init(name:"효자아트홀")],createdAt:date)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(folder)) as? [String:Any])
        json.removeValue(forKey:"referencePlanIDs")
        var venue=try XCTUnwrap((json["venues"] as? [[String:Any]])?.first)
        venue.removeValue(forKey:"createdAt");venue.removeValue(forKey:"updatedAt")
        json["venues"]=[venue]
        let decoded=try JSONDecoder().decode(PerformanceFolder.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertEqual(decoded.id,folder.id)
        XCTAssertEqual(decoded.referencePlanIDs,[planID])
        XCTAssertEqual(decoded.defaultPlanID,planID)
        XCTAssertEqual(decoded.venues.first?.id,folder.venues.first?.id)
        XCTAssertEqual(decoded.venues.first?.createdAt,date)
        let again=try JSONDecoder().decode(PerformanceFolder.self,from:JSONEncoder().encode(decoded))
        XCTAssertEqual(again,decoded)
    }

    func testSeveralScenesKeepTheirOrderWhenUpdatedOrOneIsRemoved() async throws {
        let root=directory();defer {try? FileManager.default.removeItem(at:root)}
        let store=PerformanceCatalogStore(root:root)
        _ = try await store.migrateIfNeeded(scans:[],plans:[],places:.init())
        let folder=PerformanceFolder(name:"Lion King"),other=PerformanceFolder(name:"다른 공연")
        _ = try await store.upsert(folder);_ = try await store.upsert(other)
        let first=UUID(),second=UUID(),third=UUID(),scan=UUID(),venue=PerformanceVenueTag(name:"효자아트홀")
        _ = try await store.upsertVenue(venue,in:folder.id)
        _ = try await store.assign([scan],to:folder.id,venueID:venue.id)
        for id in [first,second,third,second] {_ = try await store.addReferencePlan(id,for:folder.id)}
        _ = try await store.addReferencePlan(second,for:other.id)
        var catalog=try await store.load()
        XCTAssertEqual(catalog.performances.first {$0.id==folder.id}?.referencePlanIDs,[first,second,third])
        catalog=try await store.removeReferencePlan(second,from:folder.id)
        XCTAssertEqual(catalog.performances.first {$0.id==folder.id}?.referencePlanIDs,[first,third])
        XCTAssertEqual(catalog.performances.first {$0.id==other.id}?.referencePlanIDs,[second])
        XCTAssertEqual(catalog.assignments[scan]?.venueID,venue.id)
        XCTAssertEqual(catalog.assignments[scan]?.performanceID,folder.id)
        _ = try await store.removeReferencePlan(first,from:folder.id)
        catalog=try await store.load()
        XCTAssertEqual(catalog.performances.first {$0.id==folder.id}?.defaultPlanID,third)
    }

    func testSavingAnOlderPerformanceFormPreservesScenesAndEmptySpaces() async throws {
        let root=directory();defer {try? FileManager.default.removeItem(at:root)}
        let store=PerformanceCatalogStore(root:root)
        _ = try await store.migrateIfNeeded(scans:[],plans:[],places:.init())
        var stale=PerformanceFolder(name:"공연")
        _ = try await store.upsert(stale)
        let first=UUID(),second=UUID(),creation=Date(timeIntervalSince1970:1_600_000_000)
        let venue=PerformanceVenueTag(name:"연습실",createdAt:creation)
        _ = try await store.addReferencePlan(first,for:stale.id)
        _ = try await store.addReferencePlan(second,for:stale.id)
        _ = try await store.upsertVenue(venue,in:stale.id)
        _ = try await store.upsertVenue(.init(id:venue.id,name:"연습실 B"),in:stale.id)
        stale.name="새 공연 이름";stale.notes="편집한 설명"
        let saved=try await store.upsert(stale)
        let folder=try XCTUnwrap(saved.performances.first)
        XCTAssertEqual(folder.referencePlanIDs,[first,second])
        XCTAssertEqual(folder.venues.count,1)
        XCTAssertEqual(folder.venues[0].name,"연습실 B")
        XCTAssertEqual(folder.venues[0].createdAt,creation)
        XCTAssertGreaterThan(folder.venues[0].updatedAt,creation)
        XCTAssertTrue(saved.assignments.isEmpty)
    }

    func testReferenceDraftsAndCrossingRoutesPersistWithoutChangingScanData() async throws {
        let root=directory();defer {try? FileManager.default.removeItem(at:root)}
        let store=PerformancePlanStore(root:root)
        var empty=PerformancePlan();empty.name="빈 씬";empty.isReferenceOnly=true
        var props=empty;props.id=UUID();props.name="세트만 배치한 씬"
        props.objects=[try StageObstacle(name:"세트",kind:.other,vertices:[.init(3,2),.init(5,2),.init(5,4),.init(3,4)])]
        var route=props;route.id=UUID();route.name="기물을 통과하는 참고 동선"
        try route.append(.init(1,3));try route.append(.init(8,3));route.completeReference()
        for plan in [empty,props,route] {try await store.save(plan)}
        let stored=try await store.list()
        XCTAssertEqual(Set(stored.map(\.id)),Set([empty.id,props.id,route.id]))
        XCTAssertEqual(stored.first {$0.id==route.id}?.points,route.points)
        XCTAssertTrue(stored.first {$0.id==route.id}?.finished == true)
        // The same sketch remains invalid as an executable surveyed route / legacy plan.
        var executable=route;executable.isReferenceOnly=false
        XCTAssertThrowsError(try executable.validate())
        XCTAssertThrowsError(try empty.asLegacyData().validate())
    }

    func testReferenceProjectionDoesNotCopyScenePointsOrObjectsIntoTheScan() throws {
        var plan=PerformancePlan();plan.isReferenceOnly=true
        try plan.append(.init(1,1));try plan.append(.init(4,3));plan.completeReference()
        try plan.addObject(at:.init(7,6),platform:true)
        var draft=PreparationDraft()
        draft.corners=[.init(0,0,0),.init(6,0,0),.init(6,0,-4),.init(0,0,-4)]
        let reference=try draft.reference(for:plan)
        XCTAssertEqual(reference.points.count,2);XCTAssertEqual(reference.objects.count,1)
        XCTAssertTrue(draft.route.isEmpty);XCTAssertTrue(draft.objects.isEmpty)
        XCTAssertThrowsError(try draft.applyPlan(plan))
        XCTAssertTrue(draft.route.isEmpty);XCTAssertTrue(draft.objects.isEmpty)
        XCTAssertFalse(draft.routeFinished)
    }

    func testMovingAndRemovingReferencePointsKeepsTheirSettingsTogether() throws {
        var plan=PerformancePlan();plan.isReferenceOnly=true
        try plan.append(.init(1,1));try plan.append(.init(4,3));try plan.append(.init(8,4))
        try plan.setPointSettings(.init(name:"중간"),at:1)
        plan.completeReference()
        try plan.movePoint(at:1,to:.init(5,2))
        XCTAssertEqual(plan.points[1],.init(5,2));XCTAssertEqual(plan.settings(at:1).name,"중간")
        plan.removePoint(at:0)
        XCTAssertEqual(plan.points.count,2);XCTAssertEqual(plan.pointSettings.count,2)
        XCTAssertEqual(plan.settings(at:0).name,"중간")
        plan.removePoint(at:1)
        XCTAssertFalse(plan.finished)
        XCTAssertNoThrow(try plan.validate())
    }

    func testMissingReferenceFlagKeepsLegacyValidationAndPlanContent() throws {
        var original=PerformancePlan();original.name="원래 기본 동선"
        try original.append(.init(1,1));try original.append(.init(4,3));try original.append(.init(8,4));try original.finishRoute()
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as? [String:Any])
        json.removeValue(forKey:"isReferenceOnly")
        let old=try JSONDecoder().decode(PerformancePlan.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertFalse(old.isReferenceOnly);XCTAssertEqual(old,original)
        XCTAssertNoThrow(try old.validate())
    }
}

private extension PerformancePlan {
    func asLegacyData() -> PerformancePlan {var copy=self;copy.isReferenceOnly=false;return copy}
}
