import XCTest
@testable import HearIAmCore

final class FrontDirectionPracticeTests: XCTestCase {
    func testReferenceDoesNotImmediatelyCompleteUntilUserTurnsAway() {
        var practice = FrontDirectionPractice()
        XCTAssertTrue(practice.setReference(0))
        for (index, heading) in [0.0, 4, -7, 12, 20].enumerated() {
            XCTAssertNil(practice.update(heading: heading, time: Double(index)))
            XCTAssertEqual(practice.phase, .turnAway)
        }
        let cue = practice.update(heading: 40, time: 5)
        XCTAssertEqual(cue?.toRight, false) // Turned right: target is to the left.
        XCTAssertEqual(practice.phase, .finding)
        XCTAssertNil(practice.update(heading: 11, time: 6))
        XCTAssertEqual(practice.phase, .completed)
        XCTAssertNil(practice.update(heading: 60, time: 7)) // No new trial without user action.
        XCTAssertEqual(practice.phase, .completed)
    }
    func testBothDirectionsAndWraparoundUseShortestReturn() {
        var practice = FrontDirectionPractice()
        practice.setReference(170)
        XCTAssertEqual(practice.update(heading: -150, time: 1)?.toRight, false)
        XCTAssertEqual(practice.bearing!, -40, accuracy: 0.001)
        practice.setReference(-170)
        XCTAssertEqual(practice.update(heading: 150, time: 2)?.toRight, true)
        XCTAssertEqual(practice.bearing!, 40, accuracy: 0.001)
    }
    func testFeedbackIsIdenticalToShippingGateWhileFinding() {
        var practice = FrontDirectionPractice(deadbandDegrees: 18)
        var gate = DirectionTickGate(deadbandDegrees: 18)
        practice.setReference(10)
        for (index, heading) in [-120.0, -120, -80, -50, -20, -10, 0].enumerated() {
            let time = Double(index) * 0.3
            let expected = gate.update(time: time, bearing: HeadingMath.signedDeltaDegrees(from: heading, to: 10))
            XCTAssertEqual(practice.update(heading: heading, time: time), expected)
        }
        XCTAssertEqual(practice.phase, .completed)
    }
    func testRepeatKeepsReferenceButNewReferenceReplacesIt() {
        var practice = FrontDirectionPractice()
        practice.setReference(30)
        _ = practice.update(heading: 70, time: 1)
        _ = practice.update(heading: 30, time: 2)
        practice.repeatExercise()
        XCTAssertEqual(practice.referenceHeading, 30)
        XCTAssertEqual(practice.phase, .turnAway)
        practice.setReference(90)
        XCTAssertEqual(practice.referenceHeading, 90)
        XCTAssertEqual(practice.phase, .turnAway)
    }
    func testInvalidFlatOrStaleSampleDiscardsReference() {
        for invalid in [nil, Double.nan, Double.infinity] as [Double?] {
            var practice = FrontDirectionPractice()
            practice.setReference(0)
            _ = practice.update(heading: 45, time: 1)
            XCTAssertNil(practice.update(heading: invalid, time: 2))
            XCTAssertNil(practice.referenceHeading)
            XCTAssertEqual(practice.phase, .needsReference)
        }
        var practice = FrontDirectionPractice()
        practice.setReference(0)
        _ = practice.update(heading: 45, time: 10)
        XCTAssertNil(practice.update(heading: 0, time: 9))
        XCTAssertEqual(practice.phase, .needsReference)
        XCTAssertFalse(practice.setReference(.nan))
    }
    func testResetRequiresNewReferenceAfterSensorRestart() {
        var practice = FrontDirectionPractice()
        practice.setReference(45)
        _ = practice.update(heading: 0, time: 1)
        practice.reset()
        XCTAssertNil(practice.update(heading: 45, time: 2))
        XCTAssertEqual(practice.phase, .needsReference)
        practice.repeatExercise()
        XCTAssertNil(practice.referenceHeading)
    }
}
