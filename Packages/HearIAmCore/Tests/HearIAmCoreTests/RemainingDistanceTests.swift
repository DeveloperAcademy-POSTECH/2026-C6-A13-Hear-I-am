import XCTest
@testable import HearIAmCore

final class RemainingDistanceTests: XCTestCase {
    func testKoreanDecimalPronunciationsAndRounding() {
        for (meters,text) in [(1.5,"일점오"),(3.2,"삼점이"),(0.7,"영점칠"),(2.0,"이"),(10.1,"십점일"),(23.46,"이십삼점오"),(100.0,"백"),(0.0,"영")] {
            XCTAssertEqual(DistanceAnnouncement(meters:meters)?.line,text)
        }
        for number in [Double.nan, .infinity, -1, 1000] { XCTAssertNil(DistanceAnnouncement(meters:number)) }
    }
    func testFarThenNearSpacingUsesRemainingDistance() throws {
        var gate=RemainingDistanceGate()
        gate.didSpeak(try XCTUnwrap(gate.candidate(meters:3.2)))
        XCTAssertNil(gate.candidate(meters:2.3))
        gate.didSpeak(try XCTUnwrap(gate.candidate(meters:2.2)))
        XCTAssertNil(gate.candidate(meters:2.0))
        gate.didSpeak(try XCTUnwrap(gate.candidate(meters:1.7)))
        XCTAssertNil(gate.candidate(meters:1.3))
        XCTAssertEqual(gate.candidate(meters:1.2)?.line,"일점이")
    }
    func testExactlyTwoMetresUsesHalfMetreSpacing() throws {
        var gate=RemainingDistanceGate()
        gate.didSpeak(try XCTUnwrap(gate.candidate(meters:2.5)))
        XCTAssertNil(gate.candidate(meters:2.01))
        XCTAssertEqual(gate.candidate(meters:2)?.line,"이")
    }
    func testStoppedJitterAndBacktrackingDoNotRepeat() throws {
        var gate=RemainingDistanceGate()
        gate.didSpeak(try XCTUnwrap(gate.candidate(meters:1.5)))
        for d in [1.5,1.49,1.53,2.4,1.5,1.1] { XCTAssertNil(gate.candidate(meters:d)) }
        XCTAssertEqual(gate.candidate(meters:1)?.line,"일")
    }
    func testFastProgressReadsOnlyLatestValue() throws {
        var gate=RemainingDistanceGate()
        gate.didSpeak(try XCTUnwrap(gate.candidate(meters:6.4)))
        let latest=try XCTUnwrap(gate.candidate(meters:0.7))
        XCTAssertEqual(latest.line,"영점칠")
        gate.didSpeak(latest)
        XCTAssertNil(gate.candidate(meters:0.7))
    }
    func testDistanceIsNotConsumedUntilActuallySpoken() {
        var gate=RemainingDistanceGate()
        XCTAssertEqual(gate.candidate(meters:3.2)?.line,"삼점이")
        XCTAssertEqual(gate.candidate(meters:2.7)?.line,"이점칠")
        gate.reset();XCTAssertEqual(gate.candidate(meters:3.2)?.line,"삼점이")
    }
}
