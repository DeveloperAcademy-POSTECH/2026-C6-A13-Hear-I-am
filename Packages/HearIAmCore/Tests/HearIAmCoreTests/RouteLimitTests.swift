import XCTest
@testable import HearIAmCore

final class RouteLimitTests: XCTestCase {
    func testTwentyOnePointsRoundTripAndOverflow() throws {
        let points=(0..<21).map {FloorPoint(1+Double($0)*0.4,3)}
        let route=try StageRoute(area:PerformancePlan.area,points:points,obstacles:[],allowsOutsideEndpoints:true,pointHeights:Array(repeating:0,count:21))
        let saved=try JSONEncoder().encode(route)
        XCTAssertEqual(try JSONDecoder().decode(StageRoute.self,from:saved),route)
        XCTAssertThrowsError(try StageRoute(area:route.area,points:points+[.init(10,3)],obstacles:[]))
        var invalid=route; invalid.points.append(.init(10,3)); invalid.pointHeights=nil
        XCTAssertThrowsError(try JSONDecoder().decode(StageRoute.self,from:JSONEncoder().encode(invalid)))
        for count in [3,6] {
            let old=try StageRoute(area:route.area,points:Array(points.prefix(count)),obstacles:[],allowsOutsideEndpoints:true)
            XCTAssertEqual(try JSONDecoder().decode(StageRoute.self,from:JSONEncoder().encode(old)),old)
        }
    }
    func testPlannerAndGuidanceVisitAllTwentyTargets() throws {
        var plan=PerformancePlan()
        for i in 0..<21 { try plan.append(.init(1+Double(i)*0.4,3)) }
        XCTAssertThrowsError(try plan.append(.init(10,3)))
        try plan.finishRoute(); try plan.validate()
        let decoded=try JSONDecoder().decode(PerformancePlan.self,from:JSONEncoder().encode(plan))
        XCTAssertEqual(decoded.points.count,21)
        let route=try StageRoute(area:PerformancePlan.area,points:plan.points,obstacles:[],allowsOutsideEndpoints:true)
        var settings=GuideSettings(); settings.arrivalDwell=0.1; settings.arrivalRadius=0.1
        var guide=RouteGuide(route:route,settings:settings,usesRouteCorridor:true)
        XCTAssertTrue(guide.start(position:plan.points[0],headingDegrees:0,trackingValid:true))
        for i in 1..<21 {
            XCTAssertEqual(guide.targetIndex,i)
            _=guide.observe(time:Double(i)*0.3,position:plan.points[i],headingDegrees:0,trackingValid:true)
            _=guide.observe(time:Double(i)*0.3+0.15,position:plan.points[i],headingDegrees:0,trackingValid:true)
        }
        XCTAssertEqual(guide.state,.completed)
        plan.undoPoint()
        try plan.append(.init(10,3)); try plan.finishRoute()
    }
}
