import XCTest
@testable import HearIAmCore

final class RehearsalReturnTests: XCTestCase {
    func route(points: [FloorPoint] = [.init(1,1),.init(3,1),.init(3,4),.init(7,4),.init(7,7),.init(10,7)],
               obstacles: [StageObstacle] = [], outsideEndpoints: Bool = false) throws -> StageRoute {
        let area=try StageArea(corners:[.init(12,0,0),.init(0,0,0),.init(0,0,12),.init(12,0,12)])
        return try StageRoute(area:area,points:points,obstacles:obstacles,allowsOutsideEndpoints:outsideEndpoints)
    }
    func guide(_ route: StageRoute) -> RouteGuide {
        var settings=GuideSettings(); settings.boundaryMargin=0.01; settings.obstacleClearance=0.1
        return RouteGuide(route:route,settings:settings,usesRouteCorridor:true)
    }
    @discardableResult func arrive(_ guide: inout RouteGuide,at index: Int,from time: Double) -> GuideUpdate {
        var result=guide.observe(time:time,position:guide.route.points[index],headingDegrees:0,trackingValid:true)
        for step in 1...5 {
            result=guide.observe(time:time+Double(step)*0.2,position:guide.route.points[index],headingDegrees:0,trackingValid:true)
        }
        return result
    }
    func advanced(_ route: StageRoute,to nextTarget: Int) -> RouteGuide {
        var result=guide(route)
        XCTAssertTrue(result.start(position:route.points[0],headingDegrees:0,trackingValid:true))
        if nextTarget > 1 {
            for index in 1..<nextTarget { arrive(&result,at:index,from:Double(index)*1.2) }
        }
        XCTAssertEqual(result.targetIndex,nextTarget)
        return result
    }
    func testReturnVisitsContiguousAnchorsThenWaitsAndResumesOriginalRoute() throws {
        let original=try route(); var g=advanced(original,to:4)
        let savedSettings=g.settings
        try g.beginRehearsalReturn(to:1,position:.init(7,5),headingDegrees:170,trackingValid:true)
        XCTAssertEqual(g.route,original)
        XCTAssertEqual(g.settings.arrivalRadius,savedSettings.arrivalRadius)
        XCTAssertEqual(g.settings.arrivalDwell,savedSettings.arrivalDwell)
        XCTAssertEqual(g.targetIndex,3); XCTAssertEqual(g.activeSegmentStartIndex,4)
        XCTAssertEqual(g.rehearsalReturnDestinationIndex,1); XCTAssertTrue(g.isReturningForRehearsal)
        arrive(&g,at:3,from:10)
        XCTAssertEqual(g.targetIndex,2); XCTAssertEqual(g.activeSegmentStartIndex,3)
        arrive(&g,at:2,from:11.2)
        XCTAssertEqual(g.targetIndex,1); XCTAssertEqual(g.activeSegmentStartIndex,2)
        arrive(&g,at:1,from:12.4)
        XCTAssertEqual(g.state,.paused); XCTAssertEqual(g.pauseReason,.manual)
        XCTAssertEqual(g.rehearsalReturnArrivalIndex,1); XCTAssertFalse(g.isReturningForRehearsal)
        XCTAssertFalse(g.resume(position:original.points[1],trackingValid:true))
        XCTAssertNil(g.observe(time:14,position:original.points[1],headingDegrees:0,trackingValid:true).announcement)
        XCTAssertFalse(g.resumeForwardAfterRehearsalReturn(position:.init(3,2),trackingValid:true))
        XCTAssertFalse(g.resumeForwardAfterRehearsalReturn(position:original.points[1],trackingValid:false))
        XCTAssertTrue(g.resumeForwardAfterRehearsalReturn(position:original.points[1],trackingValid:true))
        XCTAssertEqual(g.targetIndex,2); XCTAssertEqual(g.activeSegmentStartIndex,1)
        XCTAssertNil(g.rehearsalReturnDestinationIndex); XCTAssertNil(g.rehearsalReturnArrivalIndex)
        XCTAssertEqual(g.state,.guiding); XCTAssertEqual(g.route,original)
        for index in 2...5 { arrive(&g,at:index,from:20+Double(index)*1.2) }
        XCTAssertEqual(g.state,.completed)
    }
    func testReturnIsNotGuidanceRunCompletion() throws {
        let original=try route(); var g=advanced(original,to:3)
        var run=GuidanceRun(stageID:UUID(),stageName:"연습",route:original)
        let date=Date(timeIntervalSince1970:1000)
        run.begin(at:date,uptime:1)
        try g.beginRehearsalReturn(to:2,position:.init(4,4),headingDegrees:0,trackingValid:true)
        arrive(&g,at:2,from:10)
        run.arrive(guide:g,at:date.addingTimeInterval(10),uptime:11)
        XCTAssertThrowsError(try run.record(completionSpoken:true,finishedAt:date.addingTimeInterval(10)))
        XCTAssertTrue(g.resumeForwardAfterRehearsalReturn(position:original.points[2],trackingValid:true))
        for index in 3...5 { arrive(&g,at:index,from:20+Double(index)*1.2) }
        run.arrive(guide:g,at:date.addingTimeInterval(30),uptime:31)
        XCTAssertEqual(try run.record(completionSpoken:true,finishedAt:date.addingTimeInterval(30)).route,original)
    }
    func testFutureEndpointsAndInvalidDestinationsDoNotMutateGuide() throws {
        let original=try route()
        for destination in [-1,0,4,5,99] {
            var g=advanced(original,to:4)
            XCTAssertThrowsError(try g.beginRehearsalReturn(to:destination,position:.init(7,5),headingDegrees:0,trackingValid:true)) {
                XCTAssertEqual($0 as? RehearsalReturnError,.unvisitedDestination)
            }
            XCTAssertEqual(g.targetIndex,4); XCTAssertEqual(g.state,.guiding)
            XCTAssertNil(g.rehearsalReturnDestinationIndex)
        }
    }
    func testInvalidTrackingAndOffCorridorCannotAuthorizeReturn() throws {
        let original=try route()
        let cases:[(FloorPoint,Double,Bool,RehearsalReturnError)] = [
            (.init(7,5),0,false,.trackingUnavailable),(.init(7,5),.nan,true,.trackingUnavailable),
            (.init(.nan,5),0,true,.trackingUnavailable),(.init(9,5),0,true,.positionUnsafe(.offRoute)),
            (.init(13,5),0,true,.positionUnsafe(.outsideStage))]
        for (position,heading,valid,error) in cases {
            var g=advanced(original,to:4)
            XCTAssertThrowsError(try g.beginRehearsalReturn(to:2,position:position,headingDegrees:heading,trackingValid:valid)) {
                XCTAssertEqual($0 as? RehearsalReturnError,error)
            }
            XCTAssertEqual(g.targetIndex,4); XCTAssertNil(g.rehearsalReturnDestinationIndex)
        }
    }
    func testReturnPreservesDevelopFreeEntryForChairWithLegacyEdges() throws {
        let chair=try StageObstacle(name:"의자",kind:.platform,passage:.passable,
            vertices:[.init(4,2),.init(6,2),.init(6,4),.init(4,4)],entryEdges:[3],exitEdges:[1],facingEdge:0)
        let original=try route(points:[.init(1,3),.init(3,3),.init(5,3),.init(7,3),.init(9,3)],obstacles:[chair])
        var g=advanced(original,to:4)
        XCTAssertNoThrow(try g.beginRehearsalReturn(to:1,position:.init(8,3),headingDegrees:0,trackingValid:true))
        XCTAssertEqual(g.targetIndex,3)
        XCTAssertEqual(g.route.obstacles[0].facingEdge,0)
        XCTAssertEqual(g.rehearsalReturnDestinationIndex,1)
    }
    func testActualCurrentPoseConnectorCannotCutAcrossObstacle() throws {
        let box=try StageObstacle(name:"옆 상자",kind:.box,vertices:[.init(3.35,1.55),.init(3.65,1.55),.init(3.65,1.85),.init(3.35,1.85)])
        let original=try route(obstacles:[box]); var g=advanced(original,to:2)
        let position=FloorPoint(3.8,2.3)
        XCTAssertNil(g.positionIssue(position))
        XCTAssertThrowsError(try g.beginRehearsalReturn(to:1,position:position,headingDegrees:0,trackingValid:true)) {
            XCTAssertEqual($0 as? RehearsalReturnError,.blockedByObstacle("옆 상자"))
        }
        XCTAssertEqual(g.targetIndex,2)
    }
    func testReturnPauseAndResumePreserveReverseSegment() throws {
        let original=try route(); var g=advanced(original,to:4)
        try g.beginRehearsalReturn(to:1,position:.init(7,5),headingDegrees:0,trackingValid:true)
        g.pause()
        XCTAssertEqual(g.activeSegmentStartIndex,4)
        XCTAssertTrue(g.resume(position:.init(7,5),trackingValid:true))
        XCTAssertTrue(g.isReturningForRehearsal); XCTAssertEqual(g.targetIndex,3)
        _=g.observe(time:1,position:.init(9,5),headingDegrees:0,trackingValid:true)
        XCTAssertEqual(g.pauseReason,.offRoute)
        XCTAssertFalse(g.resume(position:.init(9,5),trackingValid:true))
        XCTAssertTrue(g.resume(position:.init(7,5),trackingValid:true))
    }
    func testVersionTwoAllowsOnlyActualExternalSegmentDuringReturn() throws {
        let original=try route(points:[.init(-1,3),.init(1,3),.init(11,3),.init(13,3)],outsideEndpoints:true)
        var g=advanced(original,to:3)
        try g.beginRehearsalReturn(to:1,position:.init(12.5,3),headingDegrees:0,trackingValid:true)
        XCTAssertEqual(g.targetIndex,2); XCTAssertEqual(g.activeSegmentStartIndex,3)
        XCTAssertNil(g.positionIssue(.init(12.5,3)))
        arrive(&g,at:2,from:10)
        XCTAssertEqual(g.targetIndex,1); XCTAssertEqual(g.activeSegmentStartIndex,2)
        XCTAssertEqual(g.positionIssue(.init(12.5,3)),.outsideStage)
    }
    func testReturnKeepsCorridorCheckWithoutRestoringChairWarning() throws {
        let platform=try StageObstacle(name:"단상",kind:.platform,passage:.passable,
            vertices:[.init(4,2),.init(6,2),.init(6,4),.init(4,4)],entryEdges:[1,3],exitEdges:[1,3])
        let original=try route(points:[.init(1,3),.init(3,3),.init(5,3),.init(7,3),.init(9,3)],obstacles:[platform])
        var g=advanced(original,to:3)
        try g.beginRehearsalReturn(to:1,position:.init(5.5,3),headingDegrees:0,trackingValid:true)
        _=g.observe(time:10,position:.init(5.5,1.9),headingDegrees:0,trackingValid:true)
        XCTAssertEqual(g.state,.paused); XCTAssertEqual(g.pauseReason,.offRoute)
    }
    func testReturnArrivalNeedsOriginalDwellAndCannotAdvanceWhileHeld() throws {
        let original=try route(); var g=advanced(original,to:3)
        try g.beginRehearsalReturn(to:2,position:.init(4,4),headingDegrees:0,trackingValid:true)
        for i in 0...10 {
            _=g.observe(time:Double(i)*0.2,position:original.points[2],headingDegrees:0,trackingValid:true,allowsTargetAdvance:false)
        }
        XCTAssertNil(g.rehearsalReturnArrivalIndex); XCTAssertEqual(g.state,.guiding)
        for i in 0...3 {
            _=g.observe(time:2.2+Double(i)*0.2,position:original.points[2],headingDegrees:0,trackingValid:true)
            XCTAssertNil(g.rehearsalReturnArrivalIndex)
        }
        let result=g.observe(time:3.2,position:original.points[2],headingDegrees:0,trackingValid:true)
        XCTAssertEqual(g.rehearsalReturnArrivalIndex,2)
        XCTAssertEqual(result.announcement,"P2 지점에 도착했습니다. 계속하려면 계속이라고 말씀해주세요.")
        XCTAssertNil(g.observe(time:3.4,position:original.points[2],headingDegrees:0,trackingValid:true).announcement)
    }
    func testNoReturnBeforeStartInLegacyOrDuringAnotherReturn() throws {
        let original=try route()
        var idle=guide(original)
        XCTAssertThrowsError(try idle.beginRehearsalReturn(to:1,position:original.points[1],headingDegrees:0,trackingValid:true))
        var legacy=RouteGuide(route:original,settings:GuideSettings())
        XCTAssertTrue(legacy.start(position:original.points[0],headingDegrees:0,trackingValid:true))
        XCTAssertThrowsError(try legacy.beginRehearsalReturn(to:1,position:original.points[1],headingDegrees:0,trackingValid:true))
        var g=advanced(original,to:4)
        try g.beginRehearsalReturn(to:1,position:.init(7,5),headingDegrees:0,trackingValid:true)
        XCTAssertThrowsError(try g.beginRehearsalReturn(to:2,position:.init(7,5),headingDegrees:0,trackingValid:true))
        XCTAssertEqual(g.rehearsalReturnDestinationIndex,1); XCTAssertEqual(g.targetIndex,3)
    }
    func testPNumberResolvesPastChairMilestones() throws {
        let chair=try StageObstacle(name:"의자",kind:.platform,vertices:[.init(2.5,0.5),.init(3.5,0.5),.init(3.5,1.5),.init(2.5,1.5)],facingEdge:0)
        let original=try route(obstacles:[chair])
        let g=advanced(original,to:4)
        XCTAssertEqual(original.pointLabel(at:1),"의자1")
        XCTAssertEqual(g.rehearsalPointIndex(number:2),3)
        XCTAssertNil(g.rehearsalPointIndex(number:0))
        XCTAssertNil(g.rehearsalPointIndex(number:20))
    }
    func testReturnCancelsCurrentHoldAndForwardReentryRestoresLaterHolds() throws {
        var r=try route();try r.setHoldSeconds(8,at:2)
        var g=advanced(r,to:3)
        XCTAssertTrue(g.isHolding)
        let savedRoute=g.route
        g.pause();let remaining=g.holdRemaining
        _=g.observe(time:90,position:r.points[2],headingDegrees:0,trackingValid:true)
        XCTAssertEqual(g.holdRemaining,remaining)
        try g.beginRehearsalReturn(to:1,position:r.points[2],headingDegrees:0,trackingValid:true)
        XCTAssertFalse(g.isHolding)
        arrive(&g,at:2,from:100)
        XCTAssertFalse(g.isHolding)
        arrive(&g,at:1,from:101.2)
        XCTAssertEqual(g.rehearsalReturnArrivalIndex,1)
        XCTAssertTrue(g.resumeForwardAfterRehearsalReturn(position:r.points[1],trackingValid:true))
        _=g.observe(time:110,position:r.points[2],headingDegrees:0,trackingValid:true)
        for time in [110.2,110.4,110.6,110.81] {_=g.observe(time:time,position:r.points[2],headingDegrees:0,trackingValid:true)}
        XCTAssertEqual(g.holdRemaining,8)
        XCTAssertEqual(g.route,savedRoute)
    }

}
