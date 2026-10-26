import XCTest
@testable import HearIAmCore

/// Rules decided on 10/17: warning stages and 45° corrections; chairs and stairs since #72.
/// Stage frame: heading 0 faces the audience (−Y), so the performer's right is −X.
final class SignalRuleTests: XCTestCase {
    func square(_ x: Double, _ y: Double, size: Double=1, kind: ObstacleKind = .other, name: String="상자") throws -> StageObstacle {
        try StageObstacle(name:name,kind:kind,vertices:[.init(x,y),.init(x+size,y),.init(x+size,y+size),.init(x,y+size)])
    }

    // MARK: geometry
    func testObstacleDistanceClosestPointAndCrossings() throws {
        let box=try square(2,2)
        XCTAssertEqual(box.distance(to:.init(1,2.5)),1,accuracy:1e-9)
        XCTAssertEqual(box.distance(to:.init(2.5,2.5)),0)
        XCTAssertEqual(box.closestPoint(to:.init(1,2.5)),FloorPoint(2,2.5))
        let t=box.crossings(from:.init(0,2.5),to:.init(4,2.5))
        XCTAssertEqual(t.count,2);XCTAssertEqual(t[0],0.5,accuracy:1e-9);XCTAssertEqual(t[1],0.75,accuracy:1e-9)
        XCTAssertTrue(box.crossings(from:.init(0,0),to:.init(1,0)).isEmpty)
        XCTAssertTrue(try square(0,0,kind:.platform).isStep);XCTAssertTrue(try square(0,0,kind:.stairs).isStep);XCTAssertFalse(box.isStep)
    }
    func testBearingMatchesSpokenSectors() {
        // Facing the audience, a target at −X is on the right and +X on the left.
        XCTAssertEqual(StageHeading.bearing(from:.init(0,0),to:.init(-1,0),headingDegrees:0),90,accuracy:1e-9)
        XCTAssertEqual(StageHeading.bearing(from:.init(0,0),to:.init(1,0),headingDegrees:0),-90,accuracy:1e-9)
        XCTAssertEqual(StageHeading.sector(90),2);XCTAssertEqual(StageHeading.sector(-90),6);XCTAssertEqual(StageHeading.sector(180),4)
        XCTAssertEqual(GuidanceCue(position:.init(0,0),goal:.init(-1,0),headingDegrees:0)?.direction,"오른쪽")
    }

    // MARK: warning
    func testWarningStagesAndBearing() throws {
        let box=try square(2,2)
        var gate=WarningGate()
        // Heading −90 faces +X, straight at the box.
        let far=try XCTUnwrap(gate.update(position:.init(1,2.5),headingDegrees:-90,obstacles:[box]))
        XCTAssertEqual(far.level,.far);XCTAssertEqual(far.bearing,0,accuracy:1e-9);XCTAssertEqual(far.name,"상자")
        XCTAssertEqual(gate.update(position:.init(1.5,2.5),headingDegrees:-90,obstacles:[box])?.level,.near)
        XCTAssertEqual(gate.update(position:.init(1.7,2.5),headingDegrees:-90,obstacles:[box])?.level,.close)
        var fresh=WarningGate()
        XCTAssertNil(fresh.update(position:.init(0.9,2.5),headingDegrees:-90,obstacles:[box]))
    }
    func testWarningStageIsKeptFiveCentimetresPastItsThreshold() throws {
        let box=try square(2,2)
        var gate=WarningGate()
        func level(_ distance: Double) -> WarningLevel? { gate.update(position:.init(2-distance,2.5),headingDegrees:-90,obstacles:[box])?.level }
        XCTAssertEqual(level(0.30),.close)
        XCTAssertEqual(level(0.38),.close)
        XCTAssertEqual(level(0.41),.near)
        XCTAssertEqual(level(0.99),.far)
        XCTAssertEqual(level(1.03),.far)
        XCTAssertNil(level(1.06))
        XCTAssertNil(level(1.03))
    }
    func testOnlyObstaclesAheadWarnUnlessAlmostTouching() throws {
        let box=try square(2,2)
        var gate=WarningGate()
        // Facing the audience (heading 0) the box at +X is 90° to the left: passing beside it is quiet.
        XCTAssertNil(gate.update(position:.init(1.5,2.5),headingDegrees:0,obstacles:[box]))
        XCTAssertEqual(gate.update(position:.init(1.7,2.5),headingDegrees:0,obstacles:[box])?.level,.close)
        // Ahead within ±45° warns; a warned box stays in view up to ±55°.
        var ahead=WarningGate()
        XCTAssertEqual(ahead.update(position:.init(1.5,2.5),headingDegrees:-50,obstacles:[box])?.level,.near)
        XCTAssertEqual(ahead.update(position:.init(1.5,2.5),headingDegrees:-140,obstacles:[box])?.level,.near)
        XCTAssertNil(ahead.update(position:.init(1.5,2.5),headingDegrees:-150,obstacles:[box]))
    }
    func testPlatformsAndStairsNeverWarnAndInvalidSamplesClear() throws {
        var gate=WarningGate()
        XCTAssertNil(gate.update(position:.init(1.8,2.5),headingDegrees:0,obstacles:[try square(2,2,kind:.platform),try square(2,2,kind:.stairs)]))
        XCTAssertNotNil(gate.update(position:.init(1.8,2.5),headingDegrees:0,obstacles:[try square(2,2)]))
        XCTAssertNil(gate.update(position:.init(.nan,0),headingDegrees:0,obstacles:[try square(2,2)]))
        XCTAssertNil(gate.current)
    }

    // MARK: correction
    func testCorrectionAfterOneSecondPast45Degrees() {
        var gate=CorrectionGate()
        XCTAssertNil(gate.update(time:0,bearing:30))
        XCTAssertNil(gate.update(time:2,bearing:30))
        XCTAssertNil(gate.update(time:3,bearing:60))
        XCTAssertNil(gate.update(time:3.9,bearing:60))
        XCTAssertEqual(gate.update(time:4,bearing:60),.right)
        XCTAssertNil(gate.update(time:5,bearing:60))
        XCTAssertNil(gate.update(time:6.9,bearing:60))
        XCTAssertEqual(gate.update(time:7,bearing:60),.right)
    }
    func testCorrectionWordsAndReset() {
        var gate=CorrectionGate()
        XCTAssertNil(gate.update(time:0,bearing:-100))
        XCTAssertEqual(gate.update(time:1,bearing:-100),.left)
        XCTAssertEqual(gate.update(time:1.5,bearing:170),.back)
        XCTAssertEqual(Correction.back.line,"뒤로 도세요")
        // Coming back within 45° restarts the one-second wait.
        var other=CorrectionGate()
        XCTAssertNil(other.update(time:0,bearing:60))
        XCTAssertNil(other.update(time:0.6,bearing:30))
        XCTAssertNil(other.update(time:0.8,bearing:60))
        XCTAssertNil(other.update(time:1.5,bearing:60))
        XCTAssertEqual(other.update(time:1.8,bearing:60),.right)
        XCTAssertNil(other.update(time:2,bearing:.nan))
    }

    // MARK: direction tick (#44)
    func testDirectionTickDeadbandSpokenOnceAndStopsOnEntry() throws {
        var gate=DirectionTickGate(deadbandDegrees:12)
        // Within ±12° is completely silent (nil).
        XCTAssertNil(gate.update(time:0,bearing:0))
        XCTAssertNil(gate.update(time:0.5,bearing:11.9))
        XCTAssertNil(gate.update(time:1.0,bearing:-12.0))

        // Stepping outside to the right (+30°): speaks "오른쪽" once and ticks immediately.
        let first=try XCTUnwrap(gate.update(time:2.0,bearing:30))
        XCTAssertEqual(first.spokenWord,"오른쪽")
        XCTAssertTrue(first.toRight)
        XCTAssertTrue(first.shouldTick)

        // Immediately after, neither speech nor tick fires until the interval elapses.
        let waiting=try XCTUnwrap(gate.update(time:2.05,bearing:30))
        XCTAssertNil(waiting.spokenWord)
        XCTAssertFalse(waiting.shouldTick)

        // After the interval elapses, only the tick repeats (no repeated speech).
        let interval30=gate.interval(forAbsBearing:30)
        let second=try XCTUnwrap(gate.update(time:2.0+interval30+0.001,bearing:30))
        XCTAssertNil(second.spokenWord)
        XCTAssertTrue(second.shouldTick)
        XCTAssertTrue(second.toRight)

        // Entering ±12° immediately returns nil so active ticks stop.
        XCTAssertNil(gate.update(time:3.0,bearing:8))
        XCTAssertNil(gate.update(time:3.2,bearing:5))
    }
    func testDirectionTickSideSwitchAndProportionalCadence() throws {
        var gate=DirectionTickGate(deadbandDegrees:12)
        // Faster cadence as angle approaches ±n°.
        XCTAssertLessThan(gate.interval(forAbsBearing:15),gate.interval(forAbsBearing:45))
        XCTAssertLessThan(gate.interval(forAbsBearing:45),gate.interval(forAbsBearing:90))
        XCTAssertLessThan(gate.interval(forAbsBearing:90),gate.interval(forAbsBearing:180))
        XCTAssertEqual(gate.interval(forAbsBearing:12),DirectionTickGate.minInterval,accuracy:1e-9)
        XCTAssertEqual(gate.interval(forAbsBearing:180),DirectionTickGate.maxInterval,accuracy:1e-9)

        // Left side speaks "왼쪽", overshooting across to right speaks "오른쪽".
        let left=try XCTUnwrap(gate.update(time:0,bearing:-40))
        XCTAssertEqual(left.spokenWord,"왼쪽");XCTAssertFalse(left.toRight);XCTAssertTrue(left.shouldTick)
        let right=try XCTUnwrap(gate.update(time:0.1,bearing:25))
        XCTAssertEqual(right.spokenWord,"오른쪽");XCTAssertTrue(right.toRight);XCTAssertTrue(right.shouldTick)

        // Invalid bearing clears state and returns nil.
        XCTAssertNil(gate.update(time:0.2,bearing:.nan))
    }

    /// 10/20: after facing the target, ticking restarts only 3° past the deadband, so sway at ±12° stays quiet.
    func testDirectionTicksRestartOnlyPastTheReleaseMargin() throws {
        var gate=DirectionTickGate(deadbandDegrees:12)
        _=try XCTUnwrap(gate.update(time:0,bearing:40))
        XCTAssertNil(gate.update(time:0.1,bearing:10))
        XCTAssertTrue(gate.isAligned)
        XCTAssertNil(gate.update(time:0.2,bearing:14.9))
        XCTAssertNil(gate.update(time:0.3,bearing:-15))
        let again=try XCTUnwrap(gate.update(time:0.4,bearing:15.1))
        XCTAssertEqual(again.spokenWord,"오른쪽");XCTAssertFalse(gate.isAligned)
        // A new target starts from the deadband alone.
        gate.reset()
        XCTAssertNotNil(gate.update(time:0.5,bearing:13))
    }

    // MARK: chair and stairs (#72)
    func testPlaceNamesTheSideWithTheParticle() {
        XCTAssertEqual(SignalCopy.place(bearing:0,stairs:false),"앞에 의자")
        XCTAssertEqual(SignalCopy.place(bearing:-45,stairs:true),"앞에 계단")
        XCTAssertEqual(SignalCopy.place(bearing:46,stairs:false),"오른쪽에 의자")
        XCTAssertEqual(SignalCopy.place(bearing:-135,stairs:true),"왼쪽에 계단")
        XCTAssertEqual(SignalCopy.place(bearing:136,stairs:false),"뒤에 의자")
        XCTAssertEqual(SignalCopy.place(bearing:-180,stairs:true),"뒤에 계단")
    }
    /// Field test 10/26 (scan 89F499E3): P3 stood on the chair, P2 and P4 beside it.
    func testRouteKnowsWhichPointStandsOnAChairOrStairs() throws {
        let chair=try StageObstacle(name:"의자",kind:.platform,passage:.passable,
            vertices:[.init(2.91,1.53),.init(2.91,0.97),.init(2.31,0.94),.init(2.34,1.66)],height:0.64,entryEdges:[3],exitEdges:[0])
        let box=try square(4,2.5,size:0.5)
        let area=try StageArea(corners:[Point3(6,0,0),Point3(0,0,0),Point3(0,0,6),Point3(6,0,6)])
        let route=try StageRoute(area:area,points:[.init(1.34,2.1),.init(2.63,1.95),.init(2.62,1.26),.init(3.0,1.21),.init(4.25,2.75)],obstacles:[chair,box])
        XCTAssertEqual(route.step(at:2)?.name,"의자")
        XCTAssertEqual((0..<6).filter { route.step(at:$0) != nil },[2])
        // On 10/26 the arrival at P2 faced −87° with P3 at +90°: 「앞에 의자」 was said, now 「오른쪽에 의자」.
        let bearing=StageHeading.bearing(from:.init(2.67,1.96),to:route.points[2],headingDegrees:-86)
        XCTAssertEqual(SignalCopy.place(bearing:bearing,stairs:false),"오른쪽에 의자")
    }
    func testChairsAndStairsNeverWarnButObstaclesDo() throws {
        let chair=try square(2,2,kind:.platform,name:"의자"), stairs=try square(2,2,kind:.stairs,name:"계단")
        var closed=chair; closed.entryEdges=[]; closed.exitEdges=[]
        for step in [chair,stairs,closed] {
            var gate=WarningGate()
            for p in [FloorPoint(1.7,2.5),.init(2.5,2.5),.init(2.9,2.9)] {
                XCTAssertNil(gate.update(position:p,headingDegrees:-90,obstacles:[step]),"\(step.name) \(p)")
            }
            XCTAssertNil(step.blockingPoint(from:.init(1.7,2.5)))
        }
        var gate=WarningGate()
        XCTAssertEqual(gate.update(position:.init(1.7,2.5),headingDegrees:-90,obstacles:[try square(2,2)])?.level,.close)
    }

    // MARK: distance
    func testDistanceMarksEveryMetreThenHalfAndOncePerLeg() {
        var gate=DistanceGate()
        let target=FloorPoint(0,0)
        XCTAssertNil(gate.update(position:.init(0,3.05),target:target))
        var said: [Double]=[]
        for y in stride(from:3.0,through:0.3,by:-0.05) {
            if let mark=gate.update(position:.init(0,y),target:target) { said.append(mark) }
        }
        XCTAssertEqual(said,[2,1,0.5])
        // Swaying back across 0.5 m does not say it again.
        XCTAssertNil(gate.update(position:.init(0,0.6),target:target))
        XCTAssertNil(gate.update(position:.init(0,0.45),target:target))
        XCTAssertEqual(said.map(SignalCopy.distance),["2미터","1미터","50센티"])
    }
    func testDistanceStartsBelowTheStartAndRestartsForANewTarget() {
        var gate=DistanceGate()
        // Starting 1.05 m away: 1 m is too close to the start to be news.
        XCTAssertNil(gate.update(position:.init(0,1.05),target:.init(0,0)))
        XCTAssertNil(gate.update(position:.init(0,0.95),target:.init(0,0)))
        // A jump past several marks says only the nearest.
        XCTAssertEqual(gate.update(position:.init(0,0.4),target:.init(0,0)),0.5)
        XCTAssertNil(gate.update(position:.init(0,0.4),target:.init(0,2.5)))
        XCTAssertEqual(gate.update(position:.init(0,1.55),target:.init(0,2.5)),1)
        gate.reset()
        XCTAssertNil(gate.update(position:.init(0,1.55),target:.init(0,2.5)))
    }

    // MARK: point names (#74)
    func testPointNamesInKoreanPhonetics() {
        XCTAssertEqual(SignalCopy.point(1),"피일")
        XCTAssertEqual(SignalCopy.point(2),"피이")
        XCTAssertEqual(SignalCopy.point(3),"피삼")
        XCTAssertEqual(SignalCopy.point(4),"피사")
        XCTAssertEqual(SignalCopy.point(5),"피오")
        XCTAssertEqual(SignalCopy.point(19),"피십구")
        XCTAssertEqual(SignalCopy.point(20),"피이십")
        XCTAssertEqual(SignalCopy.point(21),"피21")
    }

    // MARK: step facing edge alignment (#76)
    func testStepFacingEdgeAlignmentThenNextSpotDirection() throws {
        let chair=try StageObstacle(name:"스툴",kind:.platform,passage:.passable,
            vertices:[.init(2,2),.init(4,2),.init(4,4),.init(2,4)],height:0.45,facingEdge:0)
        let area=try StageArea(corners:[Point3(6,0,0),Point3(0,0,0),Point3(0,0,6),Point3(6,0,6)])
        let route=try StageRoute(area:area,points:[.init(1,3),.init(3,3),.init(5,3)],obstacles:[chair])
        let reachedStep=try XCTUnwrap(route.step(at:1))
        XCTAssertEqual(reachedStep.facingEdge,0)

        // 1st step: sitting on P1 (3,3) facing -80° (stage left); green edge 0 faces audience (0°), so turn right (+80°).
        var gate=DirectionTickGate(deadbandDegrees:15)
        let firstBearing=try XCTUnwrap(reachedStep.facingBearing(headingDegrees:-80))
        XCTAssertEqual(firstBearing,80,accuracy:1e-9)
        let alignCue=try XCTUnwrap(gate.update(time:1.0,bearing:firstBearing))
        XCTAssertEqual(alignCue.spokenWord,"오른쪽")
        XCTAssertTrue(alignCue.toRight)
        XCTAssertEqual(SignalCopy.look(toRight:alignCue.toRight),"오른쪽 봐")
        XCTAssertEqual(SignalCopy.look(toRight:false),"왼쪽 봐")

        // Turning to face the green edge within ±15° completes 1st alignment.
        let alignedBearing=try XCTUnwrap(reachedStep.facingBearing(headingDegrees:-5))
        XCTAssertNil(gate.update(time:2.0,bearing:alignedBearing))
        XCTAssertTrue(gate.isAligned)

        // 2nd step: after aligned chime, reset gate and guide from P1 (3,3) toward P2 (5,3) while facing -5°.
        gate.reset()
        let nextBearing=StageHeading.bearing(from:route.points[1],to:route.points[2],headingDegrees:-5)
        let nextCue=try XCTUnwrap(gate.update(time:2.8,bearing:nextBearing))
        XCTAssertEqual(nextCue.spokenWord,"왼쪽")
        XCTAssertFalse(nextCue.toRight)
    }

    func testStepPointLabelsAndSpokenNamesPerKind() throws {
        XCTAssertEqual(SignalCopy.start,"출발")
        XCTAssertEqual(SignalCopy.stepHint(stairs:false),"의자")
        XCTAssertEqual(SignalCopy.stepHint(stairs:true),"계단")
        XCTAssertEqual(SignalCopy.stepPoint(stairs:false,number:1),"의자일")
        XCTAssertEqual(SignalCopy.stepPoint(stairs:false,number:2),"의자이")
        XCTAssertEqual(SignalCopy.stepPoint(stairs:true,number:1),"계단일")
        XCTAssertEqual(SignalCopy.stepPoint(stairs:true,number:2),"계단이")

        let chair=try StageObstacle(name:"스툴",kind:.platform,passage:.passable,
            vertices:[.init(2,1),.init(3,1),.init(3,2),.init(2,2)],height:0.45,facingEdge:0)
        let stairs=try StageObstacle(name:"계단",kind:.stairs,passage:.passable,
            vertices:[.init(4,1),.init(5,1),.init(5,2),.init(4,2)],height:0.4,facingEdge:0)
        let area=try StageArea(corners:[Point3(8,0,0),Point3(0,0,0),Point3(0,0,6),Point3(8,0,6)])
        let points: [FloorPoint]=[.init(0.5,3),.init(1.2,3),.init(2.5,1.5),.init(3.5,3),.init(4.5,1.5),.init(2.5,1.6),.init(7,3)]
        let route=try StageRoute(area:area,points:points,obstacles:[chair,stairs])

        XCTAssertEqual(route.pointNames,["출발","P1","의자1","P2","계단1","의자2","도착"])
        XCTAssertEqual((0..<points.count).map(route.pointLabel(at:)),["출발","P1","의자1","P2","계단1","의자2","도착"])
        XCTAssertEqual((0..<points.count).map(route.spokenPointName(at:)),
                       ["피영","피일","의자일","피이","계단일","의자이",GuidanceCopy.completed])
    }
}
