import XCTest
@testable import HearIAmCore

final class SteppedDirectionTests: XCTestCase {
    func settle(_ gate: inout SteppedDirectionGate, start: Double=0) -> SteppedDirectionGate.Update {
        _=gate.update(time:start,bearing:0)
        _=gate.update(time:start+0.2,bearing:0)
        return gate.update(time:start+0.4,bearing:0)
    }
    func testInitialPitchHasOnlyFourDirectionalLevels() {
        for (angle,hertz) in [(11.0,50),(90,50),(91,40),(180,40),(-11,70),(-90,70),(-91,80),(-180,80)] {
            var gate=SteppedDirectionGate()
            XCTAssertEqual(gate.update(time:0,bearing:angle).sound,.directionBuzz(hertz:hertz))
            XCTAssertEqual(gate.currentHertz,hertz)
        }
    }
    func testApproachMovesTowardSixtyInTenHertzSteps() {
        for sign in [1.0,-1] {
            var gate=SteppedDirectionGate()
            let far=gate.update(time:0,bearing:sign*140)
            XCTAssertEqual(far.sound,.directionBuzz(hertz:sign > 0 ? 40 : 80))
            let near=gate.update(time:0.1,bearing:sign*50)
            XCTAssertEqual(near.sound,.directionBuzz(hertz:sign > 0 ? 50 : 70))
            XCTAssertEqual(settle(&gate,start:0.2).sound,.directionBuzzAligned)
            XCTAssertEqual(gate.currentHertz,60)
        }
    }
    func testFixedCadenceForBothSidesAndAngleSizes() {
        for angle in [20.0,150,-20,-150] {
            var gate=SteppedDirectionGate()
            XCTAssertNotNil(gate.update(time:0,bearing:angle).sound)
            for time in [0.1,0.3,0.5,0.8] { XCTAssertNil(gate.update(time:time,bearing:angle).sound) }
            XCTAssertNotNil(gate.update(time:0.91,bearing:angle).sound)
        }
    }
    func testPitchBandChangeReplacesOldBurstImmediately() {
        var gate=SteppedDirectionGate()
        _=gate.update(time:0,bearing:20)
        let changed=gate.update(time:0.1,bearing:110)
        XCTAssertTrue(changed.stopPrevious);XCTAssertEqual(changed.sound,.directionBuzz(hertz:40))
        let side=gate.update(time:0.2,bearing:-30)
        XCTAssertTrue(side.stopPrevious);XCTAssertEqual(side.sound,.directionBuzz(hertz:70))
    }
    func testNinetyDegreeBoundaryDoesNotChatter() {
        var gate=SteppedDirectionGate()
        _=gate.update(time:0,bearing:89)
        for (time,angle) in [(0.1,91.0),(0.2,89),(0.3,94.9)] {
            _=gate.update(time:time,bearing:angle);XCTAssertEqual(gate.currentHertz,50)
        }
        XCTAssertEqual(gate.update(time:0.4,bearing:96).sound,.directionBuzz(hertz:40))
        _=gate.update(time:0.5,bearing:86);XCTAssertEqual(gate.currentHertz,40)
        XCTAssertEqual(gate.update(time:0.6,bearing:84).sound,.directionBuzz(hertz:50))
    }
    func testRearSeamRetainsPriorSideWithinEightDegrees() {
        var gate=SteppedDirectionGate()
        _=gate.update(time:0,bearing:170)
        _=gate.update(time:0.1,bearing:-179);XCTAssertEqual(gate.currentHertz,40)
        XCTAssertEqual(gate.update(time:0.2,bearing:-171).sound,.directionBuzz(hertz:80))
    }
    func testAlignmentUsesSixtyAndBellOnceThenStaysSilent() {
        var gate=SteppedDirectionGate()
        XCTAssertEqual(settle(&gate).sound,.directionBuzzAligned)
        for i in 1...30 {
            XCTAssertNil(gate.update(time:0.4+Double(i)*0.1,bearing:0).sound)
            XCTAssertEqual(gate.currentHertz,60)
        }
    }
    func testAlignmentRearmsAtSixteenDegrees() {
        var gate=SteppedDirectionGate()
        _=settle(&gate)
        XCTAssertNil(gate.update(time:0.5,bearing:-15.9).sound)
        XCTAssertEqual(gate.update(time:0.6,bearing:-16).sound,.directionBuzz(hertz:70))
        XCTAssertEqual(settle(&gate,start:0.7).sound,.directionBuzzAligned)
    }
    func testPassingFrontDoesNotConfirmOrPlaySixty() {
        var gate=SteppedDirectionGate()
        _=gate.update(time:0,bearing:20)
        let front=gate.update(time:0.1,bearing:0)
        XCTAssertTrue(front.stopPrevious);XCTAssertNil(front.sound)
        XCTAssertEqual(gate.update(time:0.2,bearing:-20).sound,.directionBuzz(hertz:70))
    }
    func testInvalidAndMissingSamplesStopWithoutAFalseConfirmation() {
        for (time,angle) in [(Double.nan,0.0),(0.2,Double.nan),(0,0),(0.8,0)] {
            var gate=SteppedDirectionGate()
            _=gate.update(time:0,bearing:0)
            let bad=gate.update(time:time,bearing:angle)
            XCTAssertTrue(bad.stopPrevious);XCTAssertNil(bad.sound)
        }
    }
    func testPauseDoesNotQueueOrRepeatConfirmation() {
        var gate=SteppedDirectionGate()
        _=gate.update(time:0,bearing:0);gate.suspend()
        XCTAssertNil(gate.update(time:10,bearing:0).sound)
        _=gate.update(time:10.2,bearing:0)
        XCTAssertEqual(gate.update(time:10.4,bearing:0).sound,.directionBuzzAligned)
        gate.suspend()
        XCTAssertNil(gate.update(time:20,bearing:0).sound)
    }
    func rms(_ values: ArraySlice<Float>) -> Double {
        sqrt(values.reduce(0) {$0+Double($1*$1)}/Double(values.count))
    }
    func projection(_ samples: [Float], hertz: Double) -> Double {
        var real=0.0, imaginary=0.0
        for (i,sample) in samples.enumerated() {
            let angle=2 * Double.pi*hertz*Double(i)/ToneRenderer.sampleRate
            real += Double(sample)*cos(angle);imaginary += Double(sample)*sin(angle)
        }
        return 2*hypot(real,imaginary)/Double(samples.count)
    }
    func testThreePulsesUseTheHighHarmonicBuzzTimbreAtAllFivePitches() {
        for hertz in SteppedDirectionGate.pitches {
            let samples=ToneRenderer.render(.directionBuzz(hertz:hertz))
            XCTAssertEqual(samples.count,ToneRenderer.count(0.25))
            XCTAssertGreaterThan(projection(samples,hertz:Double(hertz)),0.2)
            XCTAssertGreaterThan(projection(samples,hertz:Double(hertz)*4),0.07)
            for i in 0..<3 {
                let crest=ToneRenderer.count((Double(i)+0.5)/12)
                XCTAssertGreaterThan(rms(samples[(crest-220)..<(crest+220)]),0.1)
            }
            for i in 1...2 {
                let trough=ToneRenderer.count(Double(i)/12)
                XCTAssertLessThan(rms(samples[(trough-20)..<(trough+20)]),0.01)
            }
        }
    }
    func testAlignmentPlaysSixtyThenSilenceThenTheBell() {
        let samples=ToneRenderer.render(.directionBuzzAligned)
        let sixty=ToneRenderer.render(.directionBuzz(hertz:60)), bell=ToneRenderer.render(.countDirectionAligned)
        let gap=ToneRenderer.count(SteppedDirectionGate.alignmentGap)
        XCTAssertEqual(Array(samples.prefix(sixty.count)),sixty)
        XCTAssertTrue(samples[sixty.count..<sixty.count+gap].allSatisfy {$0 == 0})
        XCTAssertEqual(Array(samples.suffix(bell.count)),bell)
        XCTAssertEqual(samples.count,sixty.count+gap+bell.count)
    }
}
