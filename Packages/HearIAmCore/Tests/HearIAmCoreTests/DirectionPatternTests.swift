import XCTest
@testable import HearIAmCore

final class DirectionPatternTests: XCTestCase {
    func testFrontIsOneShortAndBackIsOneLong() throws {
        let front=try XCTUnwrap(DirectionPattern.pulses(signedDegrees:0))
        let back=try XCTUnwrap(DirectionPattern.pulses(signedDegrees:180))
        XCTAssertEqual(front.count,1);XCTAssertEqual(back.count,1)
        XCTAssertLessThan(front[0].duration,back[0].duration)
        XCTAssertEqual(DirectionPattern.pulses(signedDegrees:-180),back)
    }
    func testLeftLeadsLongAndRightLeadsWithTwoQuickThenOneShortPer30Degrees() throws {
        for magnitude in [30,60,90,120,150] {
            let left=try XCTUnwrap(DirectionPattern.pulses(signedDegrees:-magnitude))
            let right=try XCTUnwrap(DirectionPattern.pulses(signedDegrees:magnitude))
            XCTAssertEqual(left.count,1+magnitude/30)
            XCTAssertEqual(right.count,2+magnitude/30)
            XCTAssertGreaterThan(left[0].duration,right[0].duration)
            XCTAssertNotEqual(left[0].sharpness,right[0].sharpness)
        }
    }
    func testPulsesAreOrderedAndDoNotOverlap() {
        for degrees in DirectionPattern.landmarks {
            let pulses=DirectionPattern.pulses(signedDegrees:degrees) ?? []
            for (a,b) in zip(pulses,pulses.dropFirst()) { XCTAssertLessThanOrEqual(a.time+a.duration,b.time,"\(degrees)") }
            XCTAssertTrue(pulses.allSatisfy { (0...1).contains($0.intensity) && (0...1).contains($0.sharpness) })
        }
    }
    func testOnlyLandmarksHaveAPattern() {
        for degrees in [15,45,-45,200,-200] { XCTAssertNil(DirectionPattern.pulses(signedDegrees:degrees)) }
    }
    func testNamesForLogs() {
        XCTAssertEqual(DirectionPattern.name(signedDegrees:0),"front")
        XCTAssertEqual(DirectionPattern.name(signedDegrees:-180),"back")
        XCTAssertEqual(DirectionPattern.name(signedDegrees:-60),"left_60")
        XCTAssertEqual(DirectionPattern.name(signedDegrees:90),"right_90")
    }
}
