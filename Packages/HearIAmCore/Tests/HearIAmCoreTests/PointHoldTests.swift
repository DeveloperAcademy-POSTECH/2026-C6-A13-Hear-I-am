import XCTest
@testable import HearIAmCore

final class PointHoldTests: XCTestCase {
    func route() throws -> StageRoute {
        try StageRoute(area:PerformancePlan.area,points:[.init(1,2),.init(3,2),.init(5,2),.init(7,2)],obstacles:[])
    }
    func guide(seconds: Int = 2) throws -> RouteGuide {
        var r=try route(); try r.setHoldSeconds(seconds,at:1); try r.setHoldSeconds(1,at:2)
        var settings=GuideSettings();settings.arrivalDwell=0.25
        var g=RouteGuide(route:r,settings:settings,usesRouteCorridor:true,pausesForPositionIssues:false)
        XCTAssertTrue(g.start(position:r.points[0],headingDegrees:0,trackingValid:true))
        return g
    }
    @discardableResult func observe(_ g: inout RouteGuide,_ time: Double,_ index: Int = 1, valid: Bool = true) -> GuideUpdate {
        g.observe(time:time,position:g.route.points[index],headingDegrees:0,trackingValid:valid)
    }
    func testArrivalStartsHoldAndExpiryDoesNotSkipNextPoint() throws {
        var g=try guide()
        observe(&g,0)
        let arrival=observe(&g,0.25)
        XCTAssertEqual(arrival.targetIndex,2)
        XCTAssertEqual(arrival.announcement,"1번째 지점 도착.")
        XCTAssertEqual(g.holdRemaining,2)
        for step in 2...8 {
            XCTAssertNil(observe(&g,Double(step)/4,2).announcement)
            XCTAssertEqual(g.targetIndex,2)
            XCTAssertNil(g.cue(position:g.route.points[2],headingDegrees:0))
        }
        XCTAssertEqual(g.holdRemaining,0.25)
        XCTAssertNotNil(observe(&g,2.25,2).announcement)
        XCTAssertFalse(g.isHolding);XCTAssertEqual(g.targetIndex,2)
        observe(&g,2.5,2);observe(&g,2.75,2)
        XCTAssertEqual(g.targetIndex,3);XCTAssertEqual(g.holdRemaining,1)
        for time in [3.0,3.25,3.5,3.75] {observe(&g,time,3);XCTAssertEqual(g.state,.guiding)}
        observe(&g,4,3);observe(&g,4.25,3)
        XCTAssertEqual(g.state,.completed)
        XCTAssertNil(observe(&g,4.5,3).announcement)
    }
    func testZeroSecondsPreservesImmediateNextLeg() throws {
        var g=try guide(seconds:0)
        observe(&g,0)
        let arrival=observe(&g,0.25)
        XCTAssertFalse(g.isHolding)
        XCTAssertTrue(arrival.announcement?.contains("다음 p2") == true)
        XCTAssertNotNil(g.cue(position:g.route.points[1],headingDegrees:0))
    }
    func testManualPauseFreezesRemainingTimeUntilFreshResumeFrames() throws {
        var g=try guide()
        observe(&g,0);observe(&g,0.25);observe(&g,0.5)
        let remaining=g.holdRemaining
        g.pause();observe(&g,100)
        XCTAssertEqual(g.holdRemaining,remaining)
        XCTAssertTrue(g.resume(position:g.route.points[1],trackingValid:true))
        observe(&g,101)
        XCTAssertEqual(g.holdRemaining,remaining)
        observe(&g,101.25)
        XCTAssertEqual(g.holdRemaining,remaining-0.25)
        XCTAssertNil(g.cue(position:g.route.points[1],headingDegrees:0))
    }
    func testLostTrackingAndSampleGapsDoNotConsumePerformanceTime() throws {
        for invalid in [true,false] {
            var g=try guide()
            observe(&g,0);observe(&g,0.25);observe(&g,0.5)
            let remaining=g.holdRemaining
            observe(&g,invalid ? 0.75 : 10,valid:!invalid)
            XCTAssertEqual(g.state,.paused);XCTAssertEqual(g.holdRemaining,remaining)
            XCTAssertTrue(g.resume(position:g.route.points[1],trackingValid:true))
            observe(&g,20);XCTAssertEqual(g.holdRemaining,remaining)
        }
    }
    func testLegacyRouteDefaultsToZeroAndSettingsRoundTrip() throws {
        var r=try route()
        let old=try JSONDecoder().decode(StageRoute.self,from:JSONEncoder().encode(r))
        XCTAssertNil(old.pointHoldSeconds);XCTAssertEqual(old.holdSeconds(at:1),0)
        try r.setHoldSeconds(3600,at:1);try r.setHoldSeconds(12,at:2)
        let decoded=try JSONDecoder().decode(StageRoute.self,from:JSONEncoder().encode(r))
        XCTAssertEqual(decoded,r);XCTAssertEqual(decoded.holdSeconds(at:1),3600)
        try r.setHoldSeconds(0,at:1);XCTAssertEqual(r.holdSeconds(at:1),0)
    }
    func testInvalidDurationsAndEndpointsAreRejected() throws {
        var r=try route()
        for (index,seconds) in [(0,3),(3,3),(-1,3),(1,-1),(1,3601)] {
            XCTAssertThrowsError(try r.setHoldSeconds(seconds,at:index))
        }
        for values in [[0,1],[1,0,0,0],[0,0,0,1],[0,-1,0,0],[0,3601,0,0]] {
            r.pointHoldSeconds=values
            XCTAssertThrowsError(try r.validate())
            XCTAssertThrowsError(try JSONDecoder().decode(StageRoute.self,from:JSONEncoder().encode(r)))
        }
    }
    func testEditingOnePointPreservesOtherSettingsAndScanAssets() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=ScanStore(root:root), r=try route(), id=UUID(), map=Data([1,2,3])
        let mesh=MeshSnapshot(id:UUID(),transform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],vertices:[.init(0,0,0),.init(1,0,0),.init(0,0,1)],indices:[0,1,2])
        let original=try await store.save(id:id,name:"공연 무대",frame:StageFrame(origin:r.area.world(.init(0,0)),front:r.area.world(.init(0,-1))),checkpoint:r.area.world(.init(5,5)),worldMap:map,meshes:[mesh],device:"test",appVersion:"test",route:r)
        _=try await store.setPointHold(id,index:1,seconds:30)
        _=try await store.rename(id,to:"변경한 이름")
        let updated=try await store.setPointHold(id,index:2,seconds:60)
        XCTAssertEqual(updated.route?.holdSeconds(at:1),30)
        XCTAssertEqual(updated.route?.holdSeconds(at:2),60)
        XCTAssertEqual(updated.date,original.date);XCTAssertEqual(updated.name,"변경한 이름")
        XCTAssertEqual(updated.worldMapHash,original.worldMapHash);XCTAssertEqual(updated.meshHash,original.meshHash)
        XCTAssertEqual(updated.route?.points,original.route?.points)
        let loaded=try await store.load(id)
        XCTAssertEqual(loaded.worldMap,map);XCTAssertEqual(loaded.manifest.route,updated.route)
        let manifestURL=root.appendingPathComponent(id.uuidString).appendingPathComponent("manifest.json")
        let before=try Data(contentsOf:manifestURL)
        do { _=try await store.setPointHold(id,index:0,seconds:10);XCTFail("Endpoint must be rejected") } catch {}
        XCTAssertEqual(try Data(contentsOf:manifestURL),before)
        let list=try await store.list()
        XCTAssertEqual(list.first?.route?.holdSeconds(at:1),30)
    }
    func testFacingAlignmentStillBlocksProgressAfterHoldExpires() throws {
        var g=try guide(seconds:1)
        observe(&g,0);observe(&g,0.25)
        for time in [0.5,0.75,1.0,1.25,1.5,1.75,2.0] {
            _=g.observe(time:time,position:g.route.points[2],headingDegrees:0,trackingValid:true,allowsTargetAdvance:false)
            XCTAssertEqual(g.targetIndex,2)
        }
        XCTAssertFalse(g.isHolding)
        observe(&g,2.25,2);observe(&g,2.5,2)
        XCTAssertEqual(g.targetIndex,3)
    }
    func testStepNamesAndFacingEdgeRoundTripAlongsideHold() throws {
        var r=try route()
        r.obstacles=[try StageObstacle(name:"의자",kind:.platform,vertices:[.init(2.5,1.5),.init(3.5,1.5),.init(3.5,2.5),.init(2.5,2.5)],facingEdge:0)]
        r.pointNames=StageRoute.pointLabels(points:r.points,obstacles:r.obstacles)
        try r.setHoldSeconds(20,at:1)
        let decoded=try JSONDecoder().decode(StageRoute.self,from:JSONEncoder().encode(r))
        XCTAssertEqual(decoded.pointLabel(at:1),"의자1")
        XCTAssertEqual(decoded.spokenPointName(at:1),r.spokenPointName(at:1))
        XCTAssertEqual(decoded.step(at:1)?.facingEdge,0)
        XCTAssertEqual(decoded.holdSeconds(at:1),20)
        XCTAssertEqual(decoded.pointLabel(at:2),"P1")
    }

}
