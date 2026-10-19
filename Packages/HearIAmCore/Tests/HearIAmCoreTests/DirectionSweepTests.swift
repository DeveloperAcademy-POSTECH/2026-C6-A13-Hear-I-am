import XCTest
@testable import HearIAmCore

final class DirectionSweepTests: XCTestCase {
    func turn(_ update: DirectionSweepGate.Update) -> DirectionSweep.Turn? {
        if case .directionSweep(let sweep)=update.sound { return sweep.turn };return nil
    }
    func settle(_ gate: inout DirectionSweepGate, start: Double=0, bearing: Double=0) -> DirectionSweepGate.Update {
        _=gate.update(time:start,bearing:bearing)
        _=gate.update(time:start+0.2,bearing:bearing)
        return gate.update(time:start+0.4,bearing:bearing)
    }
    func testRecoveryPointsBackToRouteNotForwardToWaypoint() throws {
        let area=try StageArea(corners:[.init(6,0,0),.init(0,0,0),.init(0,0,6),.init(6,0,6)])
        let route=try StageRoute(area:area,points:[.init(2,2),.init(2,5)],obstacles:[])
        let guide=RouteGuide(route:route,settings:GuideSettings(),usesRouteCorridor:true)
        let position=FloorPoint(3,3)
        let recovery=try XCTUnwrap(guide.recoveryBearing(position:position,headingDegrees:0))
        XCTAssertEqual(recovery,90,accuracy:0.001)
        XCTAssertGreaterThan(abs(recovery-StageHeading.bearing(from:position,to:route.points[1],headingDegrees:0)),45)
        var gate=DirectionSweepGate()
        XCTAssertEqual(turn(gate.update(time:0,bearing:recovery)),.right)
        XCTAssertNil(guide.recoveryBearing(position:.init(2,3),headingDegrees:0))
        XCTAssertNil(guide.recoveryBearing(position:.init(2,3),headingDegrees:.nan))
    }
    func testBodyClockwiseFullTurnAndRearSeam() {
        var gate=DirectionSweepGate()
        XCTAssertEqual(settle(&gate).sound,.directionAligned)
        let position=FloorPoint(0,0), target=FloorPoint(0,-2)
        var time=0.4
        for (heading,expected) in [(45,DirectionSweep.Turn.left),(90,.left),(135,.left),(179,.left),(181,.left),(189,.right),(225,.right),(270,.right),(315,.right)] {
            var heard: DirectionSweep.Turn?
            for _ in 0..<10 {
                time += 0.1
                let u=gate.update(time:time,bearing:StageHeading.bearing(from:position,to:target,headingDegrees:Double(heading)))
                heard=turn(u) ?? heard
            }
            XCTAssertEqual(heard,expected,"heading \(heading)")
        }
        XCTAssertEqual(settle(&gate,start:time+0.1,bearing:0).sound,.directionAligned)
    }
    func testCounterclockwiseAndExactRearDefaults() {
        var gate=DirectionSweepGate()
        XCTAssertEqual(turn(gate.update(time:0,bearing:180)),.left)
        gate.reset()
        XCTAssertEqual(turn(gate.update(time:0,bearing:179)),.right)
        XCTAssertNil(gate.update(time:0.1,bearing:-179).sound)
        XCTAssertEqual(turn(gate.update(time:0.2,bearing:-171)),.left)
    }
    func testCadenceIsFixedForNearAndFarErrors() {
        for bearing in [-20.0,170] {
            var gate=DirectionSweepGate()
            XCTAssertNotNil(gate.update(time:0,bearing:bearing).sound)
            for t in [0.1,0.3,0.5,0.8] { XCTAssertNil(gate.update(time:t,bearing:bearing).sound) }
            XCTAssertNotNil(gate.update(time:0.86,bearing:bearing).sound)
        }
    }
    func testEntryStopsSweepAndRequiresContinuousDwell() {
        var gate=DirectionSweepGate()
        _=gate.update(time:0,bearing:-50)
        let entering=gate.update(time:0.1,bearing:9)
        XCTAssertTrue(entering.stopPrevious);XCTAssertNil(entering.sound)
        _=gate.update(time:0.3,bearing:11)
        XCTAssertNil(gate.update(time:0.4,bearing:9).sound)
        XCTAssertNil(gate.update(time:0.6,bearing:9).sound)
        XCTAssertEqual(gate.update(time:0.8,bearing:9).sound,.directionAligned)
    }
    func testAlignmentLatchesUntilSixteenDegrees() {
        var gate=DirectionSweepGate()
        XCTAssertEqual(settle(&gate,bearing:10).sound,.directionAligned)
        for (t,b) in [(0.5,0.0),(0.6,11),(0.7,-15.9),(0.8,0)] {
            XCTAssertNil(gate.update(time:t,bearing:b).sound)
        }
        XCTAssertEqual(turn(gate.update(time:0.9,bearing:16)),.right)
        XCTAssertEqual(settle(&gate,start:1,bearing:0).sound,.directionAligned)
    }
    func testCrossingThroughFrontSwitchesImmediatelyWithoutFalseConfirmation() {
        var gate=DirectionSweepGate()
        _=gate.update(time:0,bearing:-25)
        _=gate.update(time:0.1,bearing:0)
        let u=gate.update(time:0.2,bearing:25)
        XCTAssertTrue(u.stopPrevious);XCTAssertEqual(turn(u),.right)
    }
    func testBadAndStaleSamplesStopAndDoNotConfirm() {
        for (t,b) in [(Double.nan,0.0),(0.2,Double.nan),(0.2,Double.infinity),(0.0,0.0),(-1,0),(0.8,0)] {
            var gate=DirectionSweepGate()
            _=gate.update(time:0,bearing:0)
            let u=gate.update(time:t,bearing:b)
            XCTAssertTrue(u.stopPrevious);XCTAssertNil(u.sound)
            XCTAssertNil(gate.update(time:1,bearing:0).sound)
        }
    }
    func testSuspensionDoesNotQueueAlignmentOrRepeatConfirmedBeep() {
        var gate=DirectionSweepGate()
        _=gate.update(time:0,bearing:0);gate.suspend()
        XCTAssertNil(gate.update(time:4,bearing:0).sound)
        _=gate.update(time:4.2,bearing:0)
        XCTAssertEqual(gate.update(time:4.4,bearing:0).sound,.directionAligned)
        gate.suspend()
        XCTAssertNil(gate.update(time:8,bearing:0).sound)
        gate.reset() // New waypoint / recovery target starts an independent alignment.
        XCTAssertEqual(settle(&gate,start:9).sound,.directionAligned)
    }
    func frequency(_ samples: [Float], from: Double, to: Double) -> Double {
        let a=ToneRenderer.count(from), b=ToneRenderer.count(to)
        let crossings=(a+1..<b).filter { samples[$0-1] <= 0 && samples[$0] > 0 }.count
        return Double(crossings)/(to-from)
    }
    func testRenderedGlidesRiseForLeftAndFallForRight() {
        for side in [DirectionSweep.Turn.left,.right] {
            let samples=ToneRenderer.render(.directionSweep(DirectionSweep(turn:side,errorDegrees:180)))
            XCTAssertEqual(samples.count,ToneRenderer.count(DirectionSweep.duration))
            let early=frequency(samples,from:0.04,to:0.14), late=frequency(samples,from:0.30,to:0.40)
            XCTAssertTrue(side == .left ? late > early+250 : early > late+250)
        }
    }
    func testSmallAngleNarrowsPitchSpanWithoutChangingDuration() {
        let near=DirectionSweep(turn:.left,errorDegrees:20), far=DirectionSweep(turn:.left,errorDegrees:160)
        XCTAssertLessThan(near.spanHertz,far.spanHertz)
        XCTAssertEqual(ToneRenderer.render(.directionSweep(near)).count,ToneRenderer.render(.directionSweep(far)).count)
    }
    func testAlignmentHasTwoBeepsSeparatedBySilenceAndDiffersFromArrival() {
        let samples=ToneRenderer.render(.directionAligned)
        XCTAssertEqual(samples.count,ToneRenderer.count(0.29))
        let gap=samples[ToneRenderer.count(0.105)..<ToneRenderer.count(0.185)]
        XCTAssertTrue(gap.allSatisfy {$0 == 0})
        XCTAssertEqual(frequency(samples,from:0.02,to:0.08),1100,accuracy:25)
        XCTAssertEqual(frequency(samples,from:0.21,to:0.27),1100,accuracy:25)
        XCTAssertNotEqual(samples,ToneRenderer.render(.arrival))
    }
}
