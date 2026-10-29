import XCTest
@testable import HearIAmCore

final class StartAlignmentTests: XCTestCase {
    func route(delay: Int? = nil) throws -> StageRoute {
        try StageRoute(area:PerformancePlan.area,points:[.init(2,2),.init(4,2),.init(6,2)],obstacles:[],startDelaySeconds:delay)
    }
    @discardableResult func sample(_ alignment: inout StartAlignment,_ time: Double,heading: Double = -90,position: FloorPoint = .init(2,2),valid: Bool = true,allowsAdvance: Bool = true) -> StartAlignment.State {
        alignment.observe(time:time,position:position,headingDegrees:heading,trackingValid:valid,allowsAdvance:allowsAdvance)
        return alignment.state
    }
    func testExactStartToFirstPointDirectionNotEightWayRounding() throws {
        var r=try route();r.points[1] = .init(3,1.5)
        var a=try StartAlignment(route:r,settings:GuideSettings())
        let expected=StageHeading.bearing(from:r.points[0],to:r.points[1],headingDegrees:0)
        XCTAssertEqual(a.headingDegrees,expected,accuracy:0.000001)
        XCTAssertGreaterThan(abs(expected+45),15)
        for n in 0...4 {sample(&a,Double(n)/4,heading:expected)}
        XCTAssertEqual(a.state,.ready)
    }
    func testCountdownBeginsOnlyAfterFreshAlignmentAndArrivalSpeech() throws {
        var a=try StartAlignment(route:route(delay:2),settings:GuideSettings())
        for n in 0...4 {sample(&a,Double(n)/4,heading:0)}
        XCTAssertEqual(a.remaining,2);XCTAssertEqual(a.state,.aligning)
        for n in 5...9 {sample(&a,Double(n)/4,allowsAdvance:false)}
        XCTAssertEqual(a.remaining,2);XCTAssertEqual(a.state,.aligning)
        for n in 10...14 {sample(&a,Double(n)/4)}
        XCTAssertEqual(a.state,.waiting);XCTAssertEqual(a.remaining,2)
        for n in 15...21 {sample(&a,Double(n)/4);XCTAssertEqual(a.state,.waiting)}
        sample(&a,5.5)
        XCTAssertEqual(a.state,.ready);XCTAssertEqual(a.remaining,0);XCTAssertTrue(a.automaticallyStarts)
    }
    func testManualAndZeroSecondStartBothRequireAlignment() throws {
        for delay in [nil,0] as [Int?] {
            var a=try StartAlignment(route:route(delay:delay),settings:GuideSettings())
            for n in 0...3 {sample(&a,Double(n)/4);XCTAssertEqual(a.state,.aligning)}
            sample(&a,1)
            XCTAssertEqual(a.state,.ready);XCTAssertEqual(a.automaticallyStarts,delay != nil)
        }
    }
    func testTurnAwayFreezesRemainingAndRequiresAlignmentAgain() throws {
        var a=try StartAlignment(route:route(delay:2),settings:GuideSettings())
        for n in 0...5 {sample(&a,Double(n)/4)}
        XCTAssertEqual(a.remaining,1.75)
        sample(&a,1.5,heading:0)
        XCTAssertEqual(a.state,.aligning);XCTAssertEqual(a.remaining,1.75)
        for n in 7...11 {sample(&a,Double(n)/4)}
        XCTAssertEqual(a.state,.waiting);XCTAssertEqual(a.remaining,1.75)
        sample(&a,3);XCTAssertEqual(a.remaining,1.5)
    }
    func testPauseInvalidTrackingGapAndLeavingStartCannotAutoStart() throws {
        for mode in 0...4 {
            var a=try StartAlignment(route:route(delay:1),settings:GuideSettings())
            for n in 0...4 {sample(&a,Double(n)/4)}
            switch mode {
            case 0: a.pause()
            case 1: sample(&a,1.25,valid:false)
            case 2: sample(&a,10)
            case 3: sample(&a,1.25,position:.init(3,2))
            default: sample(&a,1.25,heading:.nan)
            }
            XCTAssertEqual(a.state,.paused)
            sample(&a,100)
            XCTAssertEqual(a.state,.paused);XCTAssertEqual(a.remaining,1)
            let retry=try StartAlignment(route:route(delay:1),settings:GuideSettings())
            XCTAssertEqual(retry.state,.aligning);XCTAssertEqual(retry.remaining,1)
        }
    }
    func testLegacyPersistenceAndDelayValidation() throws {
        let legacy=try JSONEncoder().encode(route())
        XCTAssertNil(try JSONDecoder().decode(StageRoute.self,from:legacy).startDelaySeconds)
        for seconds in [0,10,3600] {
            let r=try route(delay:seconds)
            XCTAssertEqual(try JSONDecoder().decode(StageRoute.self,from:JSONEncoder().encode(r)).startDelaySeconds,seconds)
        }
        for seconds in [-1,3601] {
            XCTAssertThrowsError(try route(delay:seconds))
            var r=try route();r.startDelaySeconds=seconds
            XCTAssertThrowsError(try JSONDecoder().decode(StageRoute.self,from:JSONEncoder().encode(r)))
        }
    }
    func testPreparationDoesNotAdvancePerformanceRouteAndOldStartFacingIsIgnored() throws {
        var r=try route(delay:1);try r.setFacing(.south,at:0);try r.setFacing(.west,at:1);try r.setHoldSeconds(10,at:1)
        var alignment=try StartAlignment(route:r,settings:GuideSettings())
        for n in 0...8 {sample(&alignment,Double(n)/4)}
        XCTAssertEqual(alignment.state,.ready)
        var guide=RouteGuide(route:r,settings:GuideSettings(),usesRouteCorridor:true)
        XCTAssertTrue(guide.start(position:r.points[0],headingDegrees:alignment.headingDegrees,trackingValid:true))
        XCTAssertEqual(guide.targetIndex,1);XCTAssertNil(guide.facingPointIndex);XCTAssertEqual(guide.holdRemaining,0)
        XCTAssertEqual(guide.route.facing(at:1),.west);XCTAssertEqual(guide.route.holdSeconds(at:1),10)
    }
}
