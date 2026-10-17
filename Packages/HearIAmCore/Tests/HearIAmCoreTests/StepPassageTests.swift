import XCTest
@testable import HearIAmCore

/// Platforms and stairs are walked onto (decided 10/17); every other object still blocks routes.
final class StepPassageTests: XCTestCase {
    func area() throws -> StageArea { try StageArea(corners:[Point3(6,0,0),Point3(0,0,0),Point3(0,0,6),Point3(6,0,6)]) }
    func square(_ kind: ObstacleKind, passage: PassagePolicy = .prohibited) throws -> StageObstacle {
        try StageObstacle(name:kind.rawValue,kind:kind,passage:passage,vertices:[.init(2,2),.init(4,2),.init(4,4),.init(2,4)])
    }
    func routeThrough(_ obstacle: StageObstacle) throws -> StageRoute {
        try StageRoute(area:area(),points:[.init(-1,3),.init(1,3),.init(5,3),.init(7,3)],obstacles:[obstacle],allowsOutsideEndpoints:true)
    }

    func testRoutesMayCrossPlatformsAndStairsButNotObstacles() throws {
        XCTAssertTrue(try routeThrough(square(.platform)).conflicts(boundaryMargin:0.3,obstacleClearance:0.35).isEmpty)
        XCTAssertTrue(try routeThrough(square(.stairs)).conflicts(boundaryMargin:0.3,obstacleClearance:0.35).isEmpty)
        XCTAssertFalse(try routeThrough(square(.other)).conflicts(boundaryMargin:0.3,obstacleClearance:0.35).isEmpty)
        XCTAssertFalse(try routeThrough(square(.box)).conflicts(boundaryMargin:0.3,obstacleClearance:0.35).isEmpty)
    }
    func testOlderSavesThatMarkedPlatformsProhibitedNowAllowCrossing() throws {
        let saved=try JSONEncoder().encode(square(.platform,passage:.prohibited))
        let decoded=try JSONDecoder().decode(StageObstacle.self,from:saved)
        XCTAssertEqual(decoded.passage,.prohibited)
        XCTAssertFalse(decoded.blocksPath)
        XCTAssertTrue(try routeThrough(decoded).conflicts(boundaryMargin:0.3,obstacleClearance:0.35).isEmpty)
    }
    func testNewPlatformsAndStairsAreSavedPassable() throws {
        let a=try area()
        for (kind,expected) in [(ObstacleKind.platform,PassagePolicy.passable),(.stairs,.passable),(.other,.prohibited)] {
            let world=WorldObstacle(name:"x",kind:kind,vertices:[a.world(.init(2,2)),a.world(.init(4,2)),a.world(.init(4,4))])
            XCTAssertEqual(try world.projected(in:a).passage,expected,kind.rawValue)
        }
        var plan=PerformancePlan()
        try plan.addObject(at:PerformancePlan.area.floor(Point3(6,0,-4)),platform:true)
        XCTAssertEqual(plan.objects.last?.passage,.passable)
    }
    func testGuidanceDoesNotPauseWhileWalkingAcrossAPlatform() throws {
        var settings=GuideSettings(); settings.boundaryMargin=0.01
        var guide=RouteGuide(route:try routeThrough(square(.platform)),settings:settings,usesRouteCorridor:true)
        XCTAssertTrue(guide.start(position:.init(-1,3),headingDegrees:0,trackingValid:true))
        _=guide.observe(time:0,position:.init(-0.5,3),headingDegrees:0,trackingValid:true)
        XCTAssertNil(guide.positionIssue(.init(0.9,3)))
        var blocked=RouteGuide(route:try routeThrough(square(.platform)).withObstacle(square(.other)),settings:settings,usesRouteCorridor:true)
        XCTAssertFalse(blocked.start(position:.init(-1,3),headingDegrees:0,trackingValid:true))
    }
}

private extension StageRoute {
    func withObstacle(_ o: StageObstacle) throws -> StageRoute {
        var copy=self; copy.obstacles=[o]; return copy
    }
}
