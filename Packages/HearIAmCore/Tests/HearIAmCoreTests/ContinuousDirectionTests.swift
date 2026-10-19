import XCTest
@testable import HearIAmCore

final class ContinuousDirectionTests: XCTestCase {
    func testSignedErrorMapsToHigherReferenceBand() throws {
        for (bearing,hertz) in [(-180.0,400.0),(-90,500),(0,600),(90,700),(180,800)] {
            XCTAssertEqual(try XCTUnwrap(ContinuousDirectionGate.hertz(bearing:bearing)),hertz,accuracy:0.001)
        }
        XCTAssertEqual(ContinuousDirectionGate.hertz(bearing:-900),400)
        XCTAssertEqual(ContinuousDirectionGate.hertz(bearing:900),800)
        XCTAssertNil(ContinuousDirectionGate.hertz(bearing:.nan))
    }
    func testSliderEndpointsHonorTheChosenSideWithoutHistory() {
        var left=ContinuousDirectionGate(), right=ContinuousDirectionGate()
        XCTAssertEqual(left.update(time:0,bearing:-180).hertz,400)
        XCTAssertEqual(right.update(time:0,bearing:180).hertz,800)
    }
    func testStationaryErrorHasNoCadenceOrPitchRestart() {
        var gate=ContinuousDirectionGate()
        for i in 0..<300 {
            let result=gate.update(time:Double(i)/30,bearing:-90)
            XCTAssertEqual(result.hertz,500);XCTAssertFalse(result.aligned)
        }
    }
    func testPitchChangesOnlyWithTheMeasuredError() throws {
        var gate=ContinuousDirectionGate()
        let left=[-150.0,-100,-50,-15].enumerated().map { i,angle in
            gate.update(time:Double(i)*0.1,bearing:angle).hertz!
        }
        XCTAssertEqual(left,left.sorted())
        let right=[150.0,100,50,15].enumerated().map { i,angle in
            gate.update(time:0.5+Double(i)*0.1,bearing:angle).hertz!
        }
        XCTAssertEqual(right,right.sorted(by:>))
    }
    func settle(_ gate: inout ContinuousDirectionGate, start: Double=0) -> ContinuousDirectionGate.Update {
        _=gate.update(time:start,bearing:0)
        _=gate.update(time:start+0.2,bearing:0)
        return gate.update(time:start+0.4,bearing:0)
    }
    func testAlignmentMutesToneAndChimesOnceUntilRearmed() {
        var gate=ContinuousDirectionGate()
        let aligned=settle(&gate)
        XCTAssertTrue(aligned.aligned);XCTAssertNil(aligned.hertz)
        for (time,bearing) in [(0.5,0.0),(0.6,12),(0.7,-15.9)] {
            let update=gate.update(time:time,bearing:bearing)
            XCTAssertFalse(update.aligned);XCTAssertNil(update.hertz)
        }
        XCTAssertNotNil(gate.update(time:0.8,bearing:16).hertz)
        XCTAssertTrue(settle(&gate,start:0.9).aligned)
    }
    func testPassingThroughFrontDoesNotConfirm() {
        var gate=ContinuousDirectionGate()
        _=gate.update(time:0,bearing:-30)
        XCTAssertNotNil(gate.update(time:0.1,bearing:0).hertz)
        let result=gate.update(time:0.2,bearing:30)
        XCTAssertFalse(result.aligned);XCTAssertGreaterThan(result.hertz!,600)
    }
    func testRearSeamRetainsPriorSideWithinEightDegrees() {
        var gate=ContinuousDirectionGate()
        XCTAssertLessThan(gate.update(time:0,bearing:-170).hertz!,600)
        XCTAssertLessThan(gate.update(time:0.1,bearing:179).hertz!,600)
        XCTAssertGreaterThan(gate.update(time:0.2,bearing:171).hertz!,600)
    }
    func testInvalidOrStaleSamplesMuteWithoutChiming() {
        for (time,bearing) in [(Double.nan,0.0),(0.2,Double.nan),(0,0),(0.8,0)] {
            var gate=ContinuousDirectionGate()
            _=gate.update(time:0,bearing:0)
            let result=gate.update(time:time,bearing:bearing)
            XCTAssertNil(result.hertz);XCTAssertFalse(result.aligned)
        }
    }
    func testPauseDoesNotQueueOrRepeatAlignment() {
        var gate=ContinuousDirectionGate()
        _=gate.update(time:0,bearing:0);gate.suspend()
        XCTAssertFalse(gate.update(time:10,bearing:0).aligned)
        _=gate.update(time:10.2,bearing:0)
        XCTAssertTrue(gate.update(time:10.4,bearing:0).aligned)
        gate.suspend()
        XCTAssertFalse(gate.update(time:20,bearing:0).aligned)
    }
    func testAudioCommandExpiresEvenWithoutAnotherSensorCallback() {
        let command=ContinuousToneCommand(hertz:600,updatedAt:10)
        XCTAssertEqual(command.activeHertz(at:10.4),600)
        XCTAssertNil(command.activeHertz(at:10.51))
        XCTAssertNil(command.activeHertz(at:9))
        XCTAssertNil(command.activeHertz(at:.nan))
    }
    func render(_ oscillator: inout ContinuousSineOscillator, _ count: Int, _ hertz: Double?) -> [Float] {
        var values=[Float](repeating:0,count:count)
        values.withUnsafeMutableBufferPointer { oscillator.render(into:$0,targetHertz:hertz,sampleRate:44_100) }
        return values
    }
    func testWaveformKeepsIdenticalPhaseAcrossBufferBoundaries() {
        var whole=ContinuousSineOscillator(), chunked=ContinuousSineOscillator()
        let expected=render(&whole,44_100,600)
        var actual:[Float]=[]
        for count in [512,1024,256,4096,38212] { actual += render(&chunked,count,600) }
        XCTAssertEqual(actual,expected)
    }
    func testStationaryWaveformIsOneUnpulsedRequestedFrequency() {
        for hertz in [400.0,600,800] {
            var oscillator=ContinuousSineOscillator()
            let values=render(&oscillator,44_100,hertz)
            // Check the onset too: no chirp from the reference into the requested note.
            let onset=(883..<5292).filter { values[$0-1] <= 0 && values[$0] > 0 }.count
            XCTAssertEqual(Double(onset)/0.1,hertz,accuracy:11)
            let start=13_230, end=35_280
            let crossings=(start+1..<end).filter { values[$0-1] <= 0 && values[$0] > 0 }.count
            XCTAssertEqual(Double(crossings)/0.5,hertz,accuracy:3)
            for offset in stride(from:start,to:end-441,by:441) {
                let rms=sqrt(values[offset..<offset+441].reduce(0) {$0+Double($1*$1)}/441)
                XCTAssertGreaterThan(rms,0.2) // No 12 Hz pulse or recurring silent gap.
            }
        }
    }
    func testPitchUpdateAndStopHaveNoClickOrPhaseReset() {
        var oscillator=ContinuousSineOscillator()
        let before=render(&oscillator,22_050,400)
        let after=render(&oscillator,22_050,800)
        let silence=render(&oscillator,22_050,nil)
        let all=before+after+silence
        let largest=(1..<all.count).map {abs(all[$0]-all[$0-1])}.max()!
        XCTAssertLessThan(largest,0.041)
        XCTAssertTrue(silence.suffix(441).allSatisfy {$0 == 0})
    }
}
