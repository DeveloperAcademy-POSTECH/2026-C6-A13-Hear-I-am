import XCTest
@testable import HearIAmCore

final class DirectionPatternTests: XCTestCase {
    func testFieldAssignmentOneTwoThreeShortAndLongAtFrontAndBack() throws {
        let counts=Dictionary(uniqueKeysWithValues:DirectionPattern.landmarks.map { ($0,DirectionPattern.pulses(signedDegrees:$0)?.count) })
        XCTAssertEqual(counts,[0:1,45:1,90:2,135:3,180:1,-45:1,-90:2,-135:3])
        let front=try XCTUnwrap(DirectionPattern.pulses(signedDegrees:0))[0]
        let back=try XCTUnwrap(DirectionPattern.pulses(signedDegrees:180))[0]
        let short=try XCTUnwrap(DirectionPattern.pulses(signedDegrees:45))[0]
        XCTAssertEqual(front.duration,DirectionPattern.longPulse)
        XCTAssertEqual(back.duration,DirectionPattern.longPulse)
        XCTAssertGreaterThan(front.duration,short.duration*3)
        XCTAssertEqual(DirectionPattern.pulses(signedDegrees:-180),DirectionPattern.pulses(signedDegrees:180))
    }
    func testLeftAndRightShareTheRhythm() {
        for magnitude in [45,90,135] {
            XCTAssertEqual(DirectionPattern.pulses(signedDegrees:-magnitude),DirectionPattern.pulses(signedDegrees:magnitude))
        }
    }
    func testPulsesAreOrderedAndDoNotOverlap() {
        for degrees in DirectionPattern.landmarks {
            let pulses=DirectionPattern.pulses(signedDegrees:degrees) ?? []
            for (a,b) in zip(pulses,pulses.dropFirst()) { XCTAssertLessThan(a.time+a.duration,b.time,"\(degrees)") }
            XCTAssertTrue(pulses.allSatisfy { (0...1).contains($0.intensity) && (0...1).contains($0.sharpness) })
        }
    }
    func testOnlyLandmarksHaveAPattern() {
        for degrees in [30,60,-30,200,-200] { XCTAssertNil(DirectionPattern.pulses(signedDegrees:degrees)) }
    }
    func testNamesForLogs() {
        XCTAssertEqual(DirectionPattern.name(signedDegrees:0),"front")
        XCTAssertEqual(DirectionPattern.name(signedDegrees:-180),"back")
        XCTAssertEqual(DirectionPattern.name(signedDegrees:-45),"left_45")
        XCTAssertEqual(DirectionPattern.name(signedDegrees:90),"right_90")
    }
    func testNearestLandmark() {
        XCTAssertEqual([0.0,22,23,-67,-68,170,-170,-180,200,359].map(DirectionPattern.nearest),[0,0,45,-45,-90,180,180,180,180,0])
    }
}
