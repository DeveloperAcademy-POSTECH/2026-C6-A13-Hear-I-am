import XCTest
@testable import HearIAmCore

final class PointFacingTests: XCTestCase {
    func route() throws -> StageRoute {
        try StageRoute(area:PerformancePlan.area,points:[.init(2,2),.init(4,2),.init(6,2)],obstacles:[])
    }
    func guide(start: StageFacing? = nil, middle: StageFacing? = .east, final: StageFacing? = nil, hold: Int = 2) throws -> RouteGuide {
        var route=try route()
        try route.setFacing(start,at:0);try route.setFacing(middle,at:1);try route.setFacing(final,at:2)
        try route.setHoldSeconds(hold,at:1)
        var settings=GuideSettings();settings.arrivalDwell=0.25
        var guide=RouteGuide(route:route,settings:settings,usesRouteCorridor:true,pausesForPositionIssues:false)
        XCTAssertTrue(guide.start(position:route.points[0],headingDegrees:0,trackingValid:true))
        return guide
    }
    @discardableResult func observe(_ guide: inout RouteGuide,_ time: Double,_ index: Int = 1,_ heading: Double = 90, valid: Bool = true, allowsFacing: Bool = true) -> GuideUpdate {
        guide.observe(time:time,position:guide.route.points[index],headingDegrees:heading,trackingValid:valid,allowsFacingCompletion:allowsFacing)
    }
    func testAllEightDirectionsUsePerformerRightAndWrapAcrossNorth() {
        // Stage X points audience-right; performer-right while facing front is negative X.
        let vectors: [FloorPoint]=[.init(0,-1),.init(-1,-1),.init(-1,0),.init(-1,1),.init(0,1),.init(1,1),.init(1,0),.init(1,-1)]
        for (direction,vector) in zip(StageFacing.allCases,vectors) {
            for heading in [-179.0,-45,0,45,179,359] {
                XCTAssertEqual(HeadingMath.wrapDegrees(direction.bearing(headingDegrees:heading)-StageHeading.bearing(from:.init(0,0),to:vector,headingDegrees:heading)),0,accuracy:0.00001)
            }
        }
        XCTAssertEqual(StageFacing.north.bearing(headingDegrees:359),1,accuracy:0.001)
    }
    func testLegacyRoundTripAndCorruptDirectionRejected() throws {
        var r=try route()
        let legacy=try JSONEncoder().encode(r)
        XCTAssertNil(try JSONDecoder().decode(StageRoute.self,from:legacy).facing(at:1))
        try r.setFacing(.northWest,at:0);try r.setFacing(.southEast,at:1);try r.setFacing(.west,at:2)
        XCTAssertEqual(try JSONDecoder().decode(StageRoute.self,from:JSONEncoder().encode(r)),r)
        try r.setFacing(nil,at:1);XCTAssertNil(r.facing(at:1))
        XCTAssertThrowsError(try r.setFacing(.north,at:-1))
        XCTAssertThrowsError(try r.setFacing(.north,at:3))
        r.pointFacings=[.north]
        XCTAssertThrowsError(try r.validate())
        XCTAssertThrowsError(try JSONDecoder().decode(StageRoute.self,from:JSONEncoder().encode(r)))
        var object=try XCTUnwrap(JSONSerialization.jsonObject(with:legacy) as? [String:Any])
        object["pointFacings"]=["north","invalid","south"]
        XCTAssertThrowsError(try JSONDecoder().decode(StageRoute.self,from:JSONSerialization.data(withJSONObject:object)))
    }
    func testFacingPrecedesHoldAndPreventsNextArrival() throws {
        var g=try guide()
        observe(&g,0);observe(&g,0.25)
        XCTAssertEqual(g.facingPointIndex,1);XCTAssertEqual(g.targetIndex,2);XCTAssertEqual(g.holdRemaining,0)
        for t in [0.5,0.75,1,1.25,1.5] { observe(&g,t,2);XCTAssertEqual(g.facingPointIndex,1);XCTAssertEqual(g.state,.guiding) }
        XCTAssertNil(g.cue(position:g.route.points[1],headingDegrees:90))
        for t in [1.75,2,2.25,2.5] { observe(&g,t);XCTAssertEqual(g.holdRemaining,0) }
        observe(&g,2.75)
        XCTAssertNil(g.facingPointIndex);XCTAssertEqual(g.holdRemaining,2)
        observe(&g,3);XCTAssertEqual(g.holdRemaining,1.75)
    }
    func testPauseAndInvalidTrackingResetFacingDwellWithoutLosingTarget() throws {
        for invalid in [true,false] {
            var g=try guide()
            observe(&g,0);observe(&g,0.25);observe(&g,0.5);observe(&g,0.75)
            if invalid { observe(&g,1,valid:false) } else { g.pause() }
            XCTAssertEqual(g.state,.paused);XCTAssertEqual(g.facingPointIndex,1)
            XCTAssertTrue(g.resume(position:g.route.points[1],trackingValid:true))
            for t in [10.0,10.25,10.5,10.75] {observe(&g,t);XCTAssertEqual(g.facingPointIndex,1)}
            observe(&g,11);XCTAssertNil(g.facingPointIndex);XCTAssertEqual(g.holdRemaining,2)
        }
    }
    func testSpeechAndWrongHeadingPreventFacingCompletion() throws {
        var g=try guide(hold:0)
        observe(&g,0);observe(&g,0.25)
        for n in 2...8 {observe(&g,Double(n)/4,1,0);XCTAssertEqual(g.facingPointIndex,1)}
        for n in 9...14 {observe(&g,Double(n)/4,allowsFacing:false);XCTAssertEqual(g.facingPointIndex,1)}
        for n in 15...19 {observe(&g,Double(n)/4)}
        XCTAssertNil(g.facingPointIndex);XCTAssertEqual(g.holdRemaining,0)
        XCTAssertNotNil(g.cue(position:g.route.points[1],headingDegrees:90))
    }
    func testStartAndFinalFacingsDelayFirstLegAndCompletion() throws {
        var g=try guide(start:.north,middle:nil,final:.west,hold:0)
        XCTAssertEqual(g.facingPointIndex,0)
        XCTAssertNil(g.cue(position:g.route.points[0],headingDegrees:0))
        for n in 0...4 {observe(&g,Double(n)/4,0,0)}
        XCTAssertNil(g.facingPointIndex);XCTAssertEqual(g.targetIndex,1)
        observe(&g,1.25);observe(&g,1.5)
        observe(&g,1.75,2);observe(&g,2,2)
        XCTAssertEqual(g.state,.guiding);XCTAssertEqual(g.facingPointIndex,2)
        for n in 9...12 {observe(&g,Double(n)/4,2,270);XCTAssertEqual(g.state,.guiding)}
        observe(&g,3.25,2,270)
        XCTAssertEqual(g.state,.completed);XCTAssertNil(g.facingPointIndex)
    }
    func testGapPausesWithoutCompletingFacing() throws {
        var g=try guide();observe(&g,0);observe(&g,0.25);observe(&g,0.5);observe(&g,2)
        XCTAssertEqual(g.state,.paused);XCTAssertEqual(g.pauseReason,.sampleGap);XCTAssertEqual(g.facingPointIndex,1)
    }
    func testStoreEditsAreAtomicAndPreserveMapOtherPointsAndMetadata() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root), id=UUID(), r=try route(), map=Data([1,2,3])
        let mesh=MeshSnapshot(id:UUID(),transform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],vertices:[.init(0,0,0),.init(1,0,0),.init(0,0,1)],indices:[0,1,2])
        let original=try await store.save(id:id,name:"방향 테스트",frame:StageFrame(origin:r.area.world(.init(0,0)),front:r.area.world(.init(0,-1))),checkpoint:r.area.world(.init(1,1)),worldMap:map,meshes:[mesh],device:"test",appVersion:"test",route:r,secondCheckpoint:r.area.world(.init(3,1)))
        _=try await store.setPointPerformance(id,index:0,facing:.north,seconds:0)
        _=try await store.setPointPerformance(id,index:1,facing:.east,seconds:10)
        _=try await store.setPointPerformance(id,index:2,facing:.south,seconds:0)
        _=try await store.rename(id,to:"새 이름")
        _=try await store.setPointPerformance(id,index:1,facing:.northWest,seconds:20)
        let loaded=try await store.load(id)
        XCTAssertEqual(loaded.manifest.name,"새 이름")
        XCTAssertEqual(loaded.manifest.route?.pointFacings,[.north,.northWest,.south])
        XCTAssertEqual(loaded.manifest.route?.holdSeconds(at:1),20)
        XCTAssertEqual(loaded.manifest.secondCheckpoint,original.secondCheckpoint)
        XCTAssertEqual(loaded.manifest.route?.points,r.points);XCTAssertEqual(loaded.worldMap,map)
        XCTAssertEqual(loaded.manifest.worldMapHash,original.worldMapHash);XCTAssertEqual(loaded.manifest.meshHash,original.meshHash)
        let url=root.appendingPathComponent(id.uuidString).appendingPathComponent("manifest.json")
        let before=try Data(contentsOf:url)
        do {_=try await store.setPointPerformance(id,index:0,facing:.west,seconds:10);XCTFail("Endpoint hold rejected")} catch {}
        XCTAssertEqual(try Data(contentsOf:url),before)
    }
}
