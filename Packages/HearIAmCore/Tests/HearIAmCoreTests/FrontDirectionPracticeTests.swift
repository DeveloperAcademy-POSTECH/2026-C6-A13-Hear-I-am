import XCTest
@testable import HearIAmCore

final class FrontDirectionPracticeTests: XCTestCase {
    /// Feeds one heading for `seconds` at 30 Hz, like the motion sensor; returns the time after the last sample.
    @discardableResult private func hold(_ practice: inout FrontDirectionPractice, _ heading: Double,
                                         from time: Double, seconds: Double) -> Double {
        var t = time
        while t < time + seconds { _ = practice.update(heading: heading, time: t); t += 1.0 / 30 }
        _ = practice.update(heading: heading, time: t)
        return t + 1.0 / 30
    }
    func testReferenceDoesNotImmediatelyCompleteUntilUserTurnsAway() {
        var practice = FrontDirectionPractice()
        XCTAssertTrue(practice.setReference(0))
        for (index, heading) in [0.0, 4, -7, 12, 20].enumerated() {
            XCTAssertNil(practice.update(heading: heading, time: Double(index) * 0.1))
            XCTAssertEqual(practice.phase, .turnAway)
        }
        let cue = practice.update(heading: 50, time: 0.5)
        XCTAssertEqual(cue?.toRight, false) // Turned right: target is to the left.
        XCTAssertEqual(practice.phase, .finding)
        var t = hold(&practice, 11, from: 0.6, seconds: 1.0)
        XCTAssertEqual(practice.phase, .completed)
        XCTAssertTrue(practice.completedOnce)
        t = hold(&practice, 20, from: t, seconds: 0.5) // Sway inside the departure band keeps the result.
        XCTAssertEqual(practice.phase, .completed)
        XCTAssertNotNil(practice.update(heading: 60, time: t)) // Turning away again starts the next trial by itself.
        XCTAssertEqual(practice.phase, .finding)
        hold(&practice, 5, from: t + 0.1, seconds: 1.0)
        XCTAssertEqual(practice.phase, .completed)
    }
    /// The reported bug: coming back to about 20–30° off was announced as the front under the 30° walking band.
    func testOffFrontReturnIsNotTheFrontUsingStageFacingTolerance() {
        XCTAssertEqual(FrontDirectionPractice().toleranceDegrees, RouteGuide.facingToleranceDegrees)
        for offset in [-28.0, -20, -16, 16, 20, 28] {
            var practice = FrontDirectionPractice()
            practice.setReference(0)
            _ = practice.update(heading: 60, time: 0)
            let t = hold(&practice, offset, from: 0.1, seconds: 3)
            XCTAssertEqual(practice.phase, .finding, "\(offset)° off")
            XCTAssertNotNil(practice.update(heading: offset, time: t), "\(offset)° off still guides back")
        }
    }
    func testFrontCountsOnlyAfterTheSameOneSecondDwellAsStageFacing() {
        var practice = FrontDirectionPractice()
        practice.setReference(0)
        _ = practice.update(heading: -60, time: 0)
        // Passing through the front without stopping is not success.
        var t = hold(&practice, 10, from: 0.1, seconds: 0.6)
        XCTAssertEqual(practice.phase, .finding)
        XCTAssertNotNil(practice.update(heading: 40, time: t))
        // Within the band the cues stop at once, but success waits for a full second there.
        t = hold(&practice, -14, from: t + 0.1, seconds: 0.9)
        XCTAssertEqual(practice.phase, .finding)
        XCTAssertNil(practice.update(heading: -14, time: t))
        hold(&practice, -14, from: t + 1.0 / 30, seconds: 0.2)
        XCTAssertEqual(practice.phase, .completed)
    }
    func testBothDirectionsAndWraparoundUseShortestReturn() {
        var practice = FrontDirectionPractice()
        practice.setReference(170)
        XCTAssertEqual(practice.update(heading: -140, time: 1)?.toRight, false)
        XCTAssertEqual(practice.bearing!, -50, accuracy: 0.001)
        practice.setReference(-170)
        XCTAssertEqual(practice.update(heading: 140, time: 2)?.toRight, true)
        XCTAssertEqual(practice.bearing!, 50, accuracy: 0.001)
    }
    func testFeedbackIsIdenticalToStageFacingGateWhileFinding() {
        var practice = FrontDirectionPractice()
        var gate = DirectionTickGate(deadbandDegrees: RouteGuide.facingToleranceDegrees, releaseMarginDegrees: 0)
        practice.setReference(10)
        for (index, heading) in [-120.0, -120, -80, -50, -20, -10, 0, 20, 30, 10, 10, 10, 10, 10, 10].enumerated() {
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
        hold(&practice, 30, from: 1.1, seconds: 1)
        XCTAssertEqual(practice.phase, .completed)
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
            _ = practice.update(heading: 50, time: 1)
            XCTAssertNil(practice.update(heading: invalid, time: 2))
            XCTAssertNil(practice.referenceHeading)
            XCTAssertEqual(practice.phase, .needsReference)
        }
        var practice = FrontDirectionPractice()
        practice.setReference(0)
        _ = practice.update(heading: 50, time: 10)
        XCTAssertNil(practice.update(heading: 0, time: 9))
        XCTAssertEqual(practice.phase, .needsReference)
        XCTAssertFalse(practice.setReference(.nan))
    }
    func testResetRequiresNewReferenceAfterSensorRestart() {
        var practice = FrontDirectionPractice()
        practice.setReference(50)
        _ = practice.update(heading: 0, time: 1)
        practice.reset()
        XCTAssertNil(practice.update(heading: 50, time: 2))
        XCTAssertEqual(practice.phase, .needsReference)
        practice.repeatExercise()
        XCTAssertNil(practice.referenceHeading)
    }
}
