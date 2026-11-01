import XCTest
@testable import HearIAmCore

final class PracticeEntryTests: XCTestCase {
    private func coverage() throws -> ScannedFootprint {
        try ScannedFootprint(meshes:[ScannedFootprintTests.rectangle(-4,-4,16,12)],area:PerformancePlan.area)
    }
    private func route() throws -> StageRoute {
        try StageRoute(area:PerformancePlan.area,points:[.init(2,2),.init(4,2),.init(6,2),.init(8,2)],obstacles:[])
    }
    private func arrive(_ guide: inout RouteGuide, at p: FloorPoint, start: Double) {
        for i in 0...4 {_=guide.observe(time:start+Double(i)/4,position:p,headingDegrees:0,trackingValid:true)}
    }
    func testPracticeUsesStableRestoredAnchorsWithoutCheckpointVerification() {
        var gate=TrackingGate()
        for i in 0...4 {_=gate.observe(time:Double(i)/4,normal:true,anchorsPresent:true)}
        XCTAssertFalse(gate.isReady(now:1))
        XCTAssertTrue(gate.isReady(now:1,validation:.relocalization))
        XCTAssertFalse(gate.verified)
        XCTAssertFalse(gate.isReady(now:2,validation:.relocalization))
        _=gate.observe(time:1.25,normal:true,anchorsPresent:false)
        XCTAssertFalse(gate.isReady(now:1.25,validation:.relocalization))
    }
    func testCurrentPositionStartsAtP1AndPreservesSavedRoute() throws {
        let saved=try route(), position=FloorPoint(4,5)
        var guide=RouteGuide(route:saved,settings:GuideSettings(),usesRouteCorridor:true,pausesForPositionIssues:false)
        XCTAssertFalse(guide.ready(position:position,headingDegrees:0,trackingValid:true))
        XCTAssertTrue(try guide.startPractice(position:position,headingDegrees:0,trackingValid:true,footprint:coverage()))
        XCTAssertEqual(guide.route,saved);XCTAssertEqual(guide.targetIndex,1)
        XCTAssertEqual(guide.activeSegmentStartPoint,position)
        XCTAssertNil(guide.facingPointIndex)
        XCTAssertEqual(guide.cue(position:position,headingDegrees:0)?.distance,3)
        arrive(&guide,at:saved.points[1],start:0)
        XCTAssertEqual(guide.targetIndex,2);XCTAssertNil(guide.practiceEntry)
        XCTAssertEqual(guide.route,saved)
    }
    func testP1IsNamedWaypointNotNecessarilyFirstArrayIndex() throws {
        let chair=try StageObstacle(name:"의자",kind:.platform,vertices:[.init(2.5,1.5),.init(3.5,1.5),.init(3.5,2.5),.init(2.5,2.5)])
        let saved=try StageRoute(area:PerformancePlan.area,points:[.init(1,2),.init(3,2),.init(5,2),.init(7,2)],obstacles:[chair])
        XCTAssertEqual(saved.pointLabel(at:1),"의자1");XCTAssertEqual(saved.pointLabel(at:2),"P1")
        var guide=RouteGuide(route:saved,settings:GuideSettings(),usesRouteCorridor:true)
        XCTAssertTrue(try guide.startPractice(position:.init(5,4),headingDegrees:0,trackingValid:true,footprint:coverage()))
        XCTAssertEqual(guide.targetIndex,2);XCTAssertEqual(guide.practiceFirstIndex,2)
    }
    func testInterruptedEntryAndLaterProgressResumeWithoutRestartingP1() throws {
        var saved=try route();try saved.setHoldSeconds(4,at:1);try saved.setFacing(.east,at:1)
        var guide=RouteGuide(route:saved,settings:GuideSettings(),usesRouteCorridor:true,pausesForPositionIssues:false)
        _=try guide.startPractice(position:.init(4,5),headingDegrees:0,trackingValid:true,footprint:coverage())
        guide.pause();XCTAssertTrue(guide.resume(position:.init(4,4),trackingValid:true));XCTAssertEqual(guide.targetIndex,1)
        arrive(&guide,at:saved.points[1],start:0)
        XCTAssertEqual(guide.facingPointIndex,1);XCTAssertEqual(guide.targetIndex,2)
        guide.pause();XCTAssertTrue(guide.resume(position:saved.points[1],trackingValid:true))
        XCTAssertEqual(guide.targetIndex,2);XCTAssertEqual(guide.facingPointIndex,1)
        XCTAssertThrowsError(try guide.startPractice(position:saved.points[1],headingDegrees:0,trackingValid:true,footprint:coverage()))
        XCTAssertEqual(guide.route,saved)
    }
    func testBlockedAndUnscannedEntryRejectedBeforeMutatingGuide() throws {
        var saved=try route()
        saved.obstacles=[try StageObstacle(name:"기물",kind:.box,vertices:[.init(3.5,3),.init(4.5,3),.init(4.5,4),.init(3.5,4)])]
        var guide=RouteGuide(route:saved,settings:GuideSettings(),usesRouteCorridor:true)
        XCTAssertThrowsError(try guide.startPractice(position:.init(4,5),headingDegrees:0,trackingValid:true,footprint:coverage()))
        XCTAssertEqual(guide.state,.idle);XCTAssertNil(guide.practiceEntry)
        let gap=try ScannedFootprint(meshes:[ScannedFootprintTests.rectangle(3,1,5,2.5),ScannedFootprintTests.rectangle(3,4.5,5,6)],area:PerformancePlan.area)
        XCTAssertThrowsError(try PracticeEntry(position:.init(4,5),route:route(),settings:GuideSettings(),footprint:gap))
    }
    func testEntryResumeRechecksNewCurrentPositionAgainstBlockingObjects() throws {
        var saved=try route()
        saved.obstacles=[try StageObstacle(name:"기물",kind:.box,vertices:[.init(3.5,3),.init(4.5,3),.init(4.5,4),.init(3.5,4)])]
        var guide=RouteGuide(route:saved,settings:GuideSettings(),usesRouteCorridor:true,pausesForPositionIssues:false)
        _=try guide.startPractice(position:.init(5,2),headingDegrees:0,trackingValid:true,footprint:coverage())
        guide.pause()
        XCTAssertFalse(guide.canResume(position:.init(4,5),trackingValid:true))
        XCTAssertFalse(guide.resume(position:.init(4,5),trackingValid:true));XCTAssertEqual(guide.targetIndex,1)
    }
    func testStartingAtP1UsesNormalArrivalDwellAndMissingP1Fails() throws {
        let saved=try route()
        var guide=RouteGuide(route:saved,settings:GuideSettings(),usesRouteCorridor:true)
        XCTAssertTrue(try guide.startPractice(position:saved.points[1],headingDegrees:0,trackingValid:true,footprint:coverage()))
        _=guide.observe(time:0,position:saved.points[1],headingDegrees:0,trackingValid:true)
        XCTAssertEqual(guide.targetIndex,1)
        arrive(&guide,at:saved.points[1],start:0.25)
        XCTAssertEqual(guide.targetIndex,2)
        let missing=try StageRoute(area:PerformancePlan.area,points:[.init(2,2),.init(4,2)],obstacles:[])
        XCTAssertThrowsError(try PracticeEntry(position:.init(3,2),route:missing,settings:GuideSettings(),footprint:coverage()))
    }
}
