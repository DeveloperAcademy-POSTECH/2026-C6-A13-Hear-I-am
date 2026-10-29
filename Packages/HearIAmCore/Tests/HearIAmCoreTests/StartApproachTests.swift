import XCTest
@testable import HearIAmCore

final class StartApproachTests: XCTestCase {
    func saved() throws -> StageRoute {
        try StageRoute(area:PerformancePlan.area,points:[.init(2,2),.init(4,2),.init(6,2)],obstacles:[])
    }
    func testApproachIsSeparateAndOnlyTargetsSavedStart() throws {
        var saved=try saved();try saved.setFacing(.east,at:0);try saved.setHoldSeconds(5,at:1)
        let position=FloorPoint(2,5), settings=GuideSettings()
        let approach=try StartApproach.route(from:position,to:saved,settings:settings)
        XCTAssertEqual(approach.points,[position,saved.points[0]])
        XCTAssertNil(approach.pointFacings);XCTAssertNil(approach.pointHoldSeconds)
        var guide=RouteGuide(route:approach,settings:settings,usesRouteCorridor:true)
        XCTAssertTrue(guide.start(position:position,headingDegrees:90,trackingValid:true))
        XCTAssertEqual(guide.cue(position:position,headingDegrees:90)?.distance,3)
        for n in 0...4 { _=guide.observe(time:Double(n)/4,position:saved.points[0],headingDegrees:0,trackingValid:true) }
        XCTAssertEqual(guide.state,.completed)
        var performance=RouteGuide(route:saved,settings:settings,usesRouteCorridor:true)
        XCTAssertTrue(performance.start(position:saved.points[0],headingDegrees:0,trackingValid:true))
        XCTAssertEqual(performance.targetIndex,1);XCTAssertEqual(performance.facingPointIndex,0)
    }
    func testOutsideTooNearInvalidAndBlockedApproachesRejected() throws {
        var saved=try saved();let settings=GuideSettings()
        for p in [FloorPoint(-1,2),.init(0.1,2),.init(2,2.1),.init(.nan,2)] {
            XCTAssertThrowsError(try StartApproach.route(from:p,to:saved,settings:settings))
        }
        saved.obstacles=[try StageObstacle(name:"기물",kind:.box,vertices:[.init(1,3),.init(3,3),.init(3,4),.init(1,4)])]
        XCTAssertThrowsError(try StartApproach.route(from:.init(2,5),to:saved,settings:settings))
        XCTAssertNoThrow(try StartApproach.route(from:.init(5,2),to:saved,settings:settings))
        saved.points[0] = .init(-1,2)
        XCTAssertThrowsError(try StartApproach.route(from:.init(5,2),to:saved,settings:settings))
    }
    func testApproachStopsOnDepartureFromCorridorAndStaleTracking() throws {
        let saved=try saved(), settings=GuideSettings(), position=FloorPoint(2,5)
        let route=try StartApproach.route(from:position,to:saved,settings:settings)
        for mode in 0...2 {
            var guide=RouteGuide(route:route,settings:settings,usesRouteCorridor:true)
            XCTAssertTrue(guide.start(position:position,headingDegrees:0,trackingValid:true))
            _=guide.observe(time:0,position:position,headingDegrees:0,trackingValid:true)
            let result=guide.observe(time:mode == 2 ? 2 : 0.25,position:mode == 0 ? .init(5,5) : position,headingDegrees:0,trackingValid:mode != 1)
            XCTAssertEqual(result.state,.paused)
            XCTAssertEqual(guide.pauseReason,mode == 0 ? .offRoute : mode == 1 ? .invalidSample : .sampleGap)
        }
    }
}
