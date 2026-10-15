import XCTest
@testable import PoC4Core

final class GuidanceTests: XCTestCase {
    func route(_ points: [FloorPoint] = [.init(-1,2),.init(1,2),.init(5,2),.init(7,2)], obstacles: [StageObstacle] = []) throws -> StageRoute {
        let area=try StageArea(corners:[.init(6,0,0),.init(0,0,0),.init(0,0,6),.init(6,0,6)])
        return try StageRoute(area:area,points:points,obstacles:obstacles,allowsOutsideEndpoints:true)
    }
    func guide(_ route: StageRoute) -> RouteGuide {
        var settings=GuideSettings(); settings.boundaryMargin=0.01
        return RouteGuide(route:route,settings:settings,usesRouteCorridor:true)
    }
    func arrive(_ guide: inout RouteGuide, at point: FloorPoint, from time: Double) -> GuideUpdate {
        var update=guide.observe(time:time,position:point,headingDegrees:0,trackingValid:true)
        for i in 1...5 { update=guide.observe(time:time+Double(i)*0.2,position:point,headingDegrees:0,trackingValid:true) }
        return update
    }
    func testEntryInteriorExitAndFinalAnnouncementExactlyOnce() throws {
        let r=try route(); var g=guide(r)
        XCTAssertTrue(g.start(position:r.points[0],headingDegrees:0,trackingValid:true))
        _=arrive(&g,at:r.points[1],from:1)
        XCTAssertEqual(g.targetIndex,2)
        _=arrive(&g,at:r.points[2],from:2.2)
        XCTAssertEqual(g.targetIndex,3)
        var messages:[String]=[]
        for i in 0...6 {
            let update=g.observe(time:3.4+Double(i)*0.2,position:r.points[3],headingDegrees:0,trackingValid:true)
            if let text=update.announcement { messages.append(text) }
        }
        XCTAssertEqual(g.state,.completed)
        XCTAssertEqual(messages.filter {$0 == GuidanceCopy.completed}.count,1)
        XCTAssertNil(g.observe(time:5,position:r.points[3],headingDegrees:0,trackingValid:true).announcement)
    }
    func testEntryAllowsOnlyActiveCorridorAndRequiresExplicitRecovery() throws {
        let r=try route(); var g=guide(r)
        XCTAssertFalse(RouteGuide(route:r,settings:GuideSettings()).startForTest(r.points[0]))
        XCTAssertTrue(g.start(position:r.points[0],headingDegrees:0,trackingValid:true))
        let result=g.observe(time:1,position:.init(-1,3),headingDegrees:0,trackingValid:true)
        XCTAssertEqual(result.state,.paused); XCTAssertEqual(g.pauseReason,.offRoute)
        XCTAssertEqual(g.targetIndex,1)
        XCTAssertFalse(g.resume(position:.init(-1,3),trackingValid:true))
        for i in 0...10 { XCTAssertFalse(g.observeAutomaticRecovery(time:2+Double(i)*0.2,position:r.points[0],headingDegrees:0,trackingValid:true)) }
        XCTAssertTrue(g.resume(position:r.points[0],trackingValid:true))
        XCTAssertEqual(g.targetIndex,1)
    }
    func testInteriorLegCannotUseExitCorridorEarly() throws {
        let r=try route(); var g=guide(r)
        XCTAssertTrue(g.start(position:r.points[0],headingDegrees:0,trackingValid:true))
        _=arrive(&g,at:r.points[1],from:1)
        XCTAssertEqual(g.targetIndex,2)
        _=g.observe(time:2.2,position:.init(6.1,2),headingDegrees:0,trackingValid:true)
        XCTAssertEqual(g.pauseReason,.outsideStage)
        XCTAssertFalse(g.canResume(position:.init(6.1,2),trackingValid:true))
    }
    func testDriftTowardRegisteredPlatformStopsEvenInsideCorridor() throws {
        let obstacle=try StageObstacle(name:"단상",kind:.platform,vertices:[.init(2,2.5),.init(4,2.5),.init(4,3.5),.init(2,3.5)])
        let r=try route(obstacles:[obstacle]);var g=guide(r)
        XCTAssertTrue(g.start(position:r.points[0],headingDegrees:0,trackingValid:true))
        _=arrive(&g,at:r.points[1],from:1)
        _=g.observe(time:2.2,position:.init(3,2.3),headingDegrees:0,trackingValid:true)
        XCTAssertEqual(g.pauseReason,.obstacleProximity)
        XCTAssertFalse(g.canResume(position:.init(3,2.3),trackingValid:true))
    }
    func testPauseAndTrackingFailurePreserveNextTarget() throws {
        let r=try route(); var g=guide(r)
        XCTAssertTrue(g.start(position:r.points[0],headingDegrees:0,trackingValid:true))
        _=arrive(&g,at:r.points[1],from:1);g.pause()
        XCTAssertEqual(g.targetIndex,2)
        XCTAssertTrue(g.resume(position:r.points[1],trackingValid:true))
        _=g.observe(time:3,position:r.points[2],headingDegrees:0,trackingValid:false)
        XCTAssertEqual(g.pauseReason,.invalidSample);XCTAssertEqual(g.targetIndex,2)
        XCTAssertFalse(g.resume(position:r.points[2],trackingValid:false))
    }
    func testDepartureRequiresConsecutiveFreshEligibleSamples() {
        var gate=DepartureGate()
        XCTAssertFalse(gate.observe(time:1,eligible:true))
        XCTAssertFalse(gate.observe(time:2.5,eligible:true))
        for t in [2.7,2.9,3.1,3.3] { XCTAssertFalse(gate.observe(time:t,eligible:true)) }
        XCTAssertTrue(gate.observe(time:3.5,eligible:true))
        XCTAssertFalse(gate.observe(time:3.5,eligible:true))
        XCTAssertFalse(gate.observe(time:3.6,eligible:false))
        XCTAssertFalse(gate.observe(time:3.7,eligible:true))
    }
    func testNarrationOrderAndLateCancellationCallbacks() throws {
        var q=NarrationQueue()
        let first=try XCTUnwrap(q.replace(["설명","3","2","1"]))
        XCTAssertNil(q.offerDirection("앞, 2미터"))
        XCTAssertTrue(q.finish(first.id));XCTAssertEqual(q.current?.text,"3")
        let old=try XCTUnwrap(q.current)
        let alert=try XCTUnwrap(q.replace(["잠시 멈춰주세요"]))
        XCTAssertFalse(q.finish(old.id));XCTAssertEqual(q.current?.id,alert.id)
        XCTAssertTrue(q.finish(alert.id));XCTAssertNil(q.current)
        XCTAssertNotNil(q.offerDirection("앞, 1미터"))
    }
    func testFinalSpeechCannotBeOverwrittenButCanRecoverAfterInterruption() throws {
        var q=NarrationQueue()
        let final=try XCTUnwrap(q.replace([GuidanceCopy.completed],completion:true))
        XCTAssertNil(q.replace(["설명 다시 듣기"]))
        XCTAssertNil(q.offerDirection("앞, 0미터"))
        q.cancel()
        let retry=try XCTUnwrap(q.replace([GuidanceCopy.completed],completion:true))
        XCTAssertFalse(q.finish(final.id));XCTAssertEqual(q.current?.id,retry.id)
        XCTAssertTrue(q.finish(retry.id));XCTAssertFalse(q.protectsCompletion)
    }
    func testSpokenNamesAndBodyRelativeDirections() throws {
        XCTAssertEqual(GuidanceCopy.target(1,last:5),"첫 번째 지점")
        XCTAssertEqual(GuidanceCopy.target(5,last:5),"마지막 지점")
        let cue=try XCTUnwrap(GuidanceCue(position:.init(3,3),goal:.init(2,2),headingDegrees:0))
        XCTAssertEqual(cue.direction,"오른쪽 앞")
        XCTAssertEqual(cue.symbol,"arrow.up.right")
        XCTAssertNil(GuidanceCue(position:.init(0,0),goal:.init(1,1),headingDegrees:.nan))
    }
}

private extension RouteGuide {
    func startForTest(_ p: FloorPoint) -> Bool { var copy=self;return copy.start(position:p,headingDegrees:0,trackingValid:true) }
}
