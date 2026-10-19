import XCTest
@testable import HearIAmCore

/// Rules decided on 10/17: warning stages, 45° corrections and step announcements.
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

    // MARK: step
    func testStepUpOnceWithinOneMetreAndStepDownWhenLeaving() throws {
        let platform=try square(5,0,size:2,kind:.platform,name:"단상")
        var gate=StepGate()
        XCTAssertNil(gate.update(position:.init(3.5,1),target:.init(6,1),obstacles:[platform]))
        let up=try XCTUnwrap(gate.update(position:.init(4.5,1),target:.init(6,1),obstacles:[platform]))
        XCTAssertEqual(up.kind,.up);XCTAssertEqual(up.distance,0.5,accuracy:1e-9);XCTAssertEqual(up.line,"앞에 단상, 올라갑니다")
        XCTAssertNil(gate.update(position:.init(4.6,1),target:.init(6,1),obstacles:[platform]))
        XCTAssertNil(gate.update(position:.init(5.5,1),target:.init(9,1),obstacles:[platform]))
        let down=try XCTUnwrap(gate.update(position:.init(6.2,1),target:.init(9,1),obstacles:[platform]))
        XCTAssertEqual(down.kind,.down);XCTAssertEqual(down.line,"내려갑니다")
        XCTAssertNil(gate.update(position:.init(6.5,1),target:.init(9,1),obstacles:[platform]))
    }
    func testNarrowPlatformSaysUpAndDownTogether() throws {
        let platform=try square(5,0,size:0.6,kind:.platform,name:"단상")
        var gate=StepGate()
        let over=try XCTUnwrap(gate.update(position:.init(4.5,0.3),target:.init(7,0.3),obstacles:[platform]))
        XCTAssertEqual(over.kind,.over);XCTAssertEqual(over.line,"앞에 단상, 올라갔다 내려갑니다")
        XCTAssertEqual(over.distance,0.5,accuracy:1e-9);XCTAssertEqual(try XCTUnwrap(over.across),0.6,accuracy:1e-9)
        XCTAssertNil(gate.update(position:.init(5.3,0.3),target:.init(7,0.3),obstacles:[platform]))
        XCTAssertNil(gate.update(position:.init(5.8,0.3),target:.init(7,0.3),obstacles:[platform]))
    }
    func testTargetOnThePlatformSaysOnlyUp() throws {
        let platform=try square(5,0,size:0.6,kind:.platform,name:"단상")
        var gate=StepGate()
        let up=try XCTUnwrap(gate.update(position:.init(4.5,0.3),target:.init(5.3,0.3),obstacles:[platform]))
        XCTAssertEqual(up.kind,.up);XCTAssertNil(up.across)
    }
    func testWayThroughACornerIsNotReadAsNarrow() throws {
        let platform=try square(5,0,size:2,kind:.platform,name:"단상")
        var gate=StepGate()
        // Straight through the corner (5,0) and on across the platform: 2.83 m wide on this way.
        let up=try XCTUnwrap(gate.update(position:.init(4.5,-0.5),target:.init(7.5,2.5),obstacles:[platform]))
        XCTAssertEqual(up.kind,.up);XCTAssertEqual(try XCTUnwrap(up.across),2*sqrt(2),accuracy:1e-6)
    }
    /// Field test 10/17 (scan 1BD93C66): a three-point platform whose corner the way cut through.
    /// The old rule said "step down" 0.08 m before the far edge; now both are said 1 m before.
    func testFieldPlatformCornerIsAnnouncedOnce() throws {
        let platform=try StageObstacle(name:"단상",kind:.platform,passage:.passable,
            vertices:[.init(0.7139529683203593,0.5632972875048134),.init(1.0932633337867907,0.34660957362677614),.init(1.0357488654195819,0.8491016512813823)])
        let target=FloorPoint(0.6787936946289872,0.3127485406974675)
        var gate=StepGate(), cues: [StepCue]=[]
        for p in [FloorPoint(2.2,1.6),.init(1.85,1.36),.init(1.76,1.17),.init(1.59,1.02),.init(1.41,0.74),.init(1.21,0.58),.init(1.08,0.45),.init(1.03,0.38),.init(0.9,0.33)] {
            if let cue=gate.update(position:p,target:target,obstacles:[platform]) { cues.append(cue) }
        }
        XCTAssertEqual(cues.map(\.kind),[.over],cues.map(\.detail).joined(separator:" | "))
    }
    func testStepRearmsAfterMovingAwayAndIgnoresObstacles() throws {
        let stairs=try square(5,0,size:2,kind:.stairs,name:"계단")
        var gate=StepGate()
        XCTAssertEqual(gate.update(position:.init(4.5,1),target:.init(6,1),obstacles:[stairs])?.line,"앞에 계단, 올라갑니다")
        XCTAssertNil(gate.update(position:.init(3,1),target:.init(6,1),obstacles:[stairs]))
        XCTAssertNotNil(gate.update(position:.init(4.5,1),target:.init(6,1),obstacles:[stairs]))
        var plain=StepGate()
        XCTAssertNil(plain.update(position:.init(4.5,1),target:.init(6,1),obstacles:[try square(5,0,size:2)]))
    }
    /// Field test 10/19 (scan 80DA77CD): 「내려갑니다」 on arriving on the platform, then overshooting past
    /// its corner clipped it by 0.06 m and added 「올라갔다 내려갑니다」 in the same second.
    func testOvershootPastAPlatformCornerAfterStepDownIsQuiet() throws {
        let platform=try StageObstacle(name:"단상",kind:.platform,passage:.passable,
            vertices:[.init(1.5319868935240273,1.236119042969031),.init(1.2262760832529627,1.1928760903779199),
                      .init(1.2267799840371716,1.500336987005577),.init(1.4978151934113444,1.5283740496398153)])
        let target=FloorPoint(1.3451606103406586,0.508620136078461)
        var gate=StepGate(), cues: [StepCue]=[]
        for p in [FloorPoint(1.484,1.349),.init(1.512,1.354),.init(1.541,1.36),.init(1.571,1.364),.init(1.63,1.377),.init(1.72,1.405),.init(1.81,1.41)] {
            if let cue=gate.update(position:p,target:target,obstacles:[platform]) { cues.append(cue) }
        }
        XCTAssertEqual(cues.map(\.kind),[.down],cues.map(\.detail).joined(separator:" | "))
    }
    func testWayClippingACornerByLessThanTenCentimetresIsNotAStep() throws {
        let platform=try square(5,0,size:2,kind:.platform,name:"단상")
        var gate=StepGate()
        // Through the corner (5,0) region: in at (5,0.05), out at (5.05,0), about 0.07 m on the platform.
        XCTAssertNil(gate.update(position:.init(4.5,0.55),target:.init(5.6,-0.55),obstacles:[platform]))
    }
    /// 10/19: past ±135° the escape line said 「오른쪽」 while the vibration said 「뒤」.
    func testEscapeLineFollowsTheVibrationBehind() {
        XCTAssertEqual(SignalCopy.escape(bearing:40),"멈추세요. 오른쪽으로 비켜서세요")
        XCTAssertEqual(SignalCopy.escape(bearing:-135),"멈추세요. 왼쪽으로 비켜서세요")
        XCTAssertEqual(SignalCopy.escape(bearing:136),"멈추세요. 뒤로 도세요")
        XCTAssertEqual(SignalCopy.escape(bearing:-170),"멈추세요. 뒤로 도세요")
    }
}
