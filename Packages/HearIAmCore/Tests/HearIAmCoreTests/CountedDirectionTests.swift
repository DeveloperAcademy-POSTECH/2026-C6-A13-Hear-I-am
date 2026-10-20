import XCTest
@testable import HearIAmCore

final class CountedDirectionTests: XCTestCase {
    func testSymmetricCountsAndTurnSide() {
        for (angle,count) in [(180.0,3),(91,3),(90,2),(31,2),(30,1),(11,1)] {
            for sign in [-1.0,1.0] {
                var gate=CountedDirectionGate()
                XCTAssertEqual(gate.update(time:0,bearing:sign*angle).sound,
                               .countDirection(toRight:sign > 0,count:count))
            }
        }
    }
    func testOneGroupFinishesAndNextUsesLatestCount() {
        var gate=CountedDirectionGate()
        XCTAssertEqual(gate.update(time:0,bearing:-150).sound,.countDirection(toRight:false,count:3))
        // Quickly approaching the target must not turn three beeps into a misleading partial group.
        for i in 1...11 {
            let result=gate.update(time:Double(i)/10,bearing:-20)
            XCTAssertNil(result.sound);XCTAssertFalse(result.stopPrevious)
        }
        XCTAssertEqual(gate.update(time:1.21,bearing:-20).sound,.countDirection(toRight:false,count:1))
        XCTAssertNil(gate.update(time:1.22,bearing:-20).sound)
    }
    func testAlignmentCutsGroupThenDingsOnceAndStaysSilent() {
        var gate=CountedDirectionGate()
        _=gate.update(time:0,bearing:100)
        XCTAssertTrue(gate.update(time:0.1,bearing:8).stopPrevious)
        XCTAssertNil(gate.update(time:0.3,bearing:0).sound)
        XCTAssertEqual(gate.update(time:0.46,bearing:0).sound,.countDirectionAligned)
        for i in 1...20 { XCTAssertNil(gate.update(time:0.46+Double(i)*0.1,bearing:12).sound) }
        XCTAssertTrue(gate.isAligned)
    }
    func testRearmRequiresSixteenDegreesAndAnotherDwell() {
        var gate=CountedDirectionGate()
        _=gate.update(time:0,bearing:0)
        XCTAssertEqual(gate.update(time:0.36,bearing:0).sound,.countDirectionAligned)
        XCTAssertNil(gate.update(time:0.4,bearing:15.9).sound)
        XCTAssertEqual(gate.update(time:0.5,bearing:-16).sound,.countDirection(toRight:false,count:1))
        XCTAssertNil(gate.update(time:0.6,bearing:0).sound)
        XCTAssertEqual(gate.update(time:0.96,bearing:0).sound,.countDirectionAligned)
    }
    func testPassingThroughTargetDoesNotDingAndSideChanges() {
        var gate=CountedDirectionGate()
        _=gate.update(time:0,bearing:20)
        _=gate.update(time:0.1,bearing:0)
        XCTAssertEqual(gate.update(time:0.2,bearing:-20).sound,.countDirection(toRight:false,count:1))
        XCTAssertFalse(gate.isAligned)
    }
    func testRearSeamDoesNotFlipSideFromSensorNoise() {
        var gate=CountedDirectionGate()
        _=gate.update(time:0,bearing:-170)
        XCTAssertNil(gate.update(time:0.1,bearing:179).sound)
        XCTAssertEqual(gate.toRight,false)
        XCTAssertEqual(gate.update(time:0.2,bearing:170).sound,.countDirection(toRight:true,count:3))
    }
    func testMissingSamplesDoNotConfirmOrReplayBacklog() {
        var gate=CountedDirectionGate()
        _=gate.update(time:0,bearing:0)
        let stale=gate.update(time:3,bearing:0)
        XCTAssertTrue(stale.stopPrevious);XCTAssertNil(stale.sound)
        XCTAssertNil(gate.update(time:3.1,bearing:0).sound)
        XCTAssertEqual(gate.update(time:3.46,bearing:0).sound,.countDirectionAligned)
        gate.suspend()
        XCTAssertNil(gate.update(time:8,bearing:0).sound) // Do not repeat confirmed ding after speech.
        XCTAssertEqual(gate.update(time:8.1,bearing:100).sound,.countDirection(toRight:true,count:3))
    }
    func testBadInputCancelsPendingDwell() {
        for bad in [Double.nan, .infinity] {
            var gate=CountedDirectionGate()
            _=gate.update(time:0,bearing:0)
            XCTAssertTrue(gate.update(time:0.1,bearing:bad).stopPrevious)
            XCTAssertNil(gate.update(time:0.4,bearing:0).sound)
        }
    }
    func testDistanceSpeechWaitsForWholeBellAndDoesNotRestartDirectionBeep() {
        let duration=Double(ToneRenderer.render(.countDirectionAligned).count)/ToneRenderer.sampleRate
        XCTAssertGreaterThan(CountedDirectionGate.narrationDelay,duration)
        var direction=CountedDirectionGate(), narration=RouteNarrationGate()
        _=direction.update(time:0,bearing:5)
        XCTAssertEqual(direction.update(time:0.36,bearing:5).sound,.countDirectionAligned)
        let readyAt=0.36+CountedDirectionGate.narrationDelay
        narration.observe(targetIndex:1,time:0.36,position:.init(0,0),heading:0,obstacles:[])
        for i in 4...10 {
            let time=Double(i)/10
            XCTAssertNil(direction.update(time:time,bearing:5).sound)
            XCTAssertNil(narration.candidate(time:time,meters:3.2,eligible:time >= readyAt,
                                             position:.init(0,0),heading:0,obstacles:[]))
        }
        let distance=narration.candidate(time:1.1,meters:3.2,eligible:direction.isAligned && 1.1 >= readyAt,
                                         position:.init(0,0),heading:0,obstacles:[])
        XCTAssertEqual(distance?.line,"삼점이")
        direction.suspend() // Actual guidance suspends direction sounds while speech plays.
        XCTAssertNil(direction.update(time:2,bearing:5).sound)
        XCTAssertTrue(direction.isAligned)
        XCTAssertEqual(direction.update(time:2.1,bearing:-20).sound,.countDirection(toRight:false,count:1))
    }
    func testRenderedGroupsHaveExactCountPitchAndSilence() {
        for right in [true,false] {
            for count in 1...3 {
                let samples=ToneRenderer.render(.countDirection(toRight:right,count:count))
                let on=ToneRenderer.count(0.12), gap=ToneRenderer.count(0.12)
                XCTAssertEqual(samples.count,count*on+(count-1)*gap)
                for pulse in 0..<count {
                    let start=pulse*(on+gap)
                    let wave=Array(samples[start..<(start+on)])
                    let crossings=zip(wave,wave.dropFirst()).filter { $0.0 <= 0 && $0.1 > 0 }.count
                    XCTAssertEqual(Double(crossings)/0.12,right ? 600 : 1200,accuracy:9)
                    XCTAssertGreaterThan(wave.map(abs).max() ?? 0,0.8)
                    if pulse < count-1 { XCTAssertTrue(samples[(start+on)..<(start+on+gap)].allSatisfy { abs($0)<0.0001 }) }
                }
                XCTAssertLessThan(Double(samples.count)/ToneRenderer.sampleRate,CountedDirectionGate.interval)
            }
        }
        XCTAssertNotEqual(ToneRenderer.render(.countDirectionAligned),ToneRenderer.render(.arrival))
        XCTAssertTrue(ToneRenderer.render(.countDirection(toRight:true,count:0)).isEmpty)
        XCTAssertTrue(ToneRenderer.render(.countDirection(toRight:false,count:4)).isEmpty)
    }
}
