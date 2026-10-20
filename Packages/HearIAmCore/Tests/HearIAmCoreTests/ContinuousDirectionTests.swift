import XCTest
@testable import HearIAmCore

final class ContinuousDirectionTests: XCTestCase {
    func testDirectionPolarityAndReferenceFrequencies() {
        for (angle,hertz) in [(-180.0,80.0),(-90,70),(0,60),(90,50),(180,40)] {
            XCTAssertEqual(ContinuousDirectionGate.hertz(bearing:angle),hertz)
        }
        XCTAssertNil(ContinuousDirectionGate.hertz(bearing:.nan))
    }
    func testDefaultGradientIncludesIntermediateFrequencies() throws {
        let actual=try XCTUnwrap(ContinuousDirectionGate.hertz(bearing:-123.4))
        XCTAssertEqual(actual,73.711111,accuracy:0.00001)
        XCTAssertEqual(ContinuousDirectionGate.hertz(bearing:135),45)
        XCTAssertEqual(ContinuousDirectionGate.hertz(bearing:-135),75)
    }
    func testTenHertzOptionChangesOnlyPitchNotCadence() {
        for (angle,hertz) in [(20.0,50.0),(120,40),(-20,70),(-120,80),(0,60)] {
            var gate=ContinuousDirectionGate(resolution:.tenHertz)
            for i in 0..<90 {
                XCTAssertEqual(gate.update(time:Double(i)/30,bearing:angle).hertz,hertz)
            }
        }
    }
    func testApproachingTargetMovesMonotonicallyTowardSixty() {
        for sign in [-1.0,1] {
            var gate=ContinuousDirectionGate()
            let notes=[180.0,150,120,90,60,30,0].enumerated().map {i,error in
                gate.update(time:Double(i)*0.1,bearing:sign*error).hertz!
            }
            XCTAssertEqual(notes,notes.sorted(by:sign < 0 ? (>) : (<)))
            XCTAssertEqual(notes.last,60)
        }
    }
    func settle(_ gate: inout ContinuousDirectionGate, start: Double=0) -> ContinuousDirectionGate.Update {
        _=gate.update(time:start,bearing:0)
        _=gate.update(time:start+0.2,bearing:0)
        return gate.update(time:start+0.4,bearing:0)
    }
    func testAlignmentChimesOnceWhileSixtyContinues() {
        var gate=ContinuousDirectionGate()
        XCTAssertTrue(settle(&gate).aligned)
        for i in 1...90 {
            let update=gate.update(time:0.4+Double(i)/30,bearing:0)
            XCTAssertEqual(update.hertz,60);XCTAssertFalse(update.aligned)
        }
    }
    func testAlignmentRearmsAtSixteenDegrees() {
        var gate=ContinuousDirectionGate()
        _=settle(&gate)
        XCTAssertEqual(gate.update(time:0.5,bearing:15).hertz,60)
        XCTAssertLessThan(gate.update(time:0.6,bearing:16).hertz!,60)
        XCTAssertTrue(settle(&gate,start:0.7).aligned)
    }
    func testBadOrStaleInputMutesAndCannotConfirm() {
        for (time,angle) in [(Double.nan,0.0),(0.2,Double.nan),(0,0),(0.8,0)] {
            var gate=ContinuousDirectionGate()
            _=gate.update(time:0,bearing:0)
            let update=gate.update(time:time,bearing:angle)
            XCTAssertNil(update.hertz);XCTAssertFalse(update.aligned)
        }
    }
    func testPauseDoesNotQueueOrRepeatAChime() {
        var gate=ContinuousDirectionGate()
        _=gate.update(time:0,bearing:0);gate.suspend()
        XCTAssertFalse(gate.update(time:10,bearing:0).aligned)
        _=gate.update(time:10.2,bearing:0)
        XCTAssertTrue(gate.update(time:10.4,bearing:0).aligned)
        gate.suspend()
        let resumed=gate.update(time:20,bearing:0)
        XCTAssertEqual(resumed.hertz,60);XCTAssertFalse(resumed.aligned)
    }
    func testRearSeamKeepsPriorSideWithinEightDegrees() {
        var gate=ContinuousDirectionGate()
        _=gate.update(time:0,bearing:-170)
        XCTAssertGreaterThan(gate.update(time:0.1,bearing:179).hertz!,60)
        XCTAssertLessThan(gate.update(time:0.2,bearing:171).hertz!,60)
    }
    func testAudioCommandExpiresWithoutAnyFurtherCallback() {
        let command=ContinuousToneCommand(hertz:60,updatedAt:10)
        XCTAssertEqual(command.activeHertz(at:10.4),60)
        XCTAssertNil(command.activeHertz(at:10.51))
        XCTAssertNil(command.activeHertz(at:9))
    }
    func render(_ oscillator: inout ContinuousHarmonicOscillator, count: Int, hertz: Double?, volume: Double=0.12) -> [Float] {
        var values=[Float](repeating:0,count:count)
        values.withUnsafeMutableBufferPointer {oscillator.render(into:$0,targetHertz:hertz,volume:volume,sampleRate:44_100)}
        return values
    }
    func testBufferBoundariesNeverRestartPhaseOrEnvelope() {
        var whole=ContinuousHarmonicOscillator(), chunks=ContinuousHarmonicOscillator()
        let expected=render(&whole,count:44_100,hertz:60)
        var actual:[Float]=[]
        for count in [512,1024,256,4096,38212] { actual += render(&chunks,count:count,hertz:60) }
        XCTAssertEqual(actual,expected)
    }
    func testStationaryToneHasNoPulseOrRepeatedSilentGapForThreeSeconds() {
        for hertz in [40.0,50,60,70,80] {
            var oscillator=ContinuousHarmonicOscillator()
            let values=render(&oscillator,count:132_300,hertz:hertz)
            var levels:[Double]=[]
            for start in stride(from:13_230,to:127_890,by:4410) {
                let window=values[start..<start+4410]
                levels.append(sqrt(window.reduce(0) {$0+Double($1*$1)}/4410))
            }
            XCTAssertGreaterThan(levels.min()!,0.06) // Catches the old repeated note/silence envelope.
            XCTAssertLessThan(levels.max()!-levels.min()!,0.0001)
            XCTAssertLessThanOrEqual(values.map(abs).max()!,0.12)
        }
    }
    func projection(_ samples: ArraySlice<Float>, hertz: Double) -> Double {
        var real=0.0, imaginary=0.0
        for (i,sample) in samples.enumerated() {
            let angle=2 * Double.pi*hertz*Double(i)/44_100
            real += Double(sample)*cos(angle);imaginary += Double(sample)*sin(angle)
        }
        return 2*hypot(real,imaginary)/Double(samples.count)
    }
    func testHigherHarmonicIsPresentWithoutTwelveHertzPulsing() {
        for hertz in [40.0,60,80] {
            var oscillator=ContinuousHarmonicOscillator()
            let values=render(&oscillator,count:44_100,hertz:hertz)
            let stable=values[22_050..<44_100]
            XCTAssertGreaterThan(projection(stable,hertz:hertz),0.08)
            XCTAssertGreaterThan(projection(stable,hertz:hertz*4),0.025)
            XCTAssertLessThan(projection(stable,hertz:hertz+12),0.001)
        }
    }
    func testFrequencyChangeAndStopStaySmoothAndQuiet() {
        var oscillator=ContinuousHarmonicOscillator()
        let values=render(&oscillator,count:22_050,hertz:80)+render(&oscillator,count:22_050,hertz:60)+render(&oscillator,count:22_050,hertz:nil)
        XCTAssertLessThan((1..<values.count).map {abs(values[$0]-values[$0-1])}.max()!,0.004)
        XCTAssertTrue(values.suffix(441).allSatisfy {$0 == 0})
    }
    func testFreshToneStartsAtItsRequestedPitchAndVolumeIsBounded() {
        var oscillator=ContinuousHarmonicOscillator()
        let values=render(&oscillator,count:8820,hertz:80,volume:1)
        XCTAssertGreaterThan(projection(values[4410..<8820],hertz:80),0.2)
        XCTAssertLessThanOrEqual(values.map(abs).max()!,0.3)
    }
}
