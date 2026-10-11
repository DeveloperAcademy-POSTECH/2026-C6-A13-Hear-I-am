import XCTest
@testable import OrientationCore

final class AngleLandmarkDetectorTests: XCTestCase {
    func testDefaultLeftAndRightAnglesAndLabels() throws {
        XCTAssertEqual(AngleCue.defaults.map(\.signedDegrees), DirectionReference.signedLandmarks)
        XCTAssertEqual(AngleCue(signedDegrees: -30).label, "왼쪽 30°")
        XCTAssertEqual(AngleCue(signedDegrees: 45).label, "오른쪽 45°")
        let cue = AngleCue(signedDegrees: -90)
        XCTAssertEqual(try JSONDecoder().decode(AngleCue.self, from: JSONEncoder().encode(cue)), cue)
        for angle in DirectionReference.signedLandmarks {
            var detector = AngleLandmarkDetector()
            detector.update(relativeDegrees: Double(angle) - 10)
            XCTAssertEqual(detector.update(relativeDegrees: Double(angle))?.signedDegrees, angle)
        }
    }

    func testEntryHysteresisAndExactThresholds() {
        var detector = AngleLandmarkDetector(cues: [.init(signedDegrees: 30)])
        XCTAssertNil(detector.update(relativeDegrees: 26.9))
        XCTAssertEqual(detector.update(relativeDegrees: 27)?.signedDegrees, 30)
        for angle in [29.0, 30, 32, 34, 35.9, 36, 31, 27] {
            XCTAssertNil(detector.update(relativeDegrees: angle), "angle=\(angle)")
        }
        XCTAssertNil(detector.update(relativeDegrees: 23.9))
        XCTAssertNil(detector.update(relativeDegrees: 26.9))
        XCTAssertEqual(detector.update(relativeDegrees: 27)?.signedDegrees, 30)
    }

    func testCrossingOutsideWindowStillFiresAndDoesNotQueueOlderCues() {
        var detector = AngleLandmarkDetector()
        XCTAssertEqual(detector.update(relativeDegrees: 0)?.signedDegrees, 0)
        XCTAssertEqual(detector.update(relativeDegrees: 80)?.signedDegrees, 60)
        XCTAssertNil(detector.update(relativeDegrees: 81))
        XCTAssertNil(detector.update(relativeDegrees: 82))
        // The return crosses 60° and 30°; the newest front cue wins.
        XCTAssertEqual(detector.update(relativeDegrees: 0)?.signedDegrees, 0)
        XCTAssertNil(detector.update(relativeDegrees: 0))
        XCTAssertEqual(detector.update(relativeDegrees: -100)?.signedDegrees, -90)
        XCTAssertNil(detector.update(relativeDegrees: -101))
        XCTAssertEqual(detector.update(relativeDegrees: 0)?.signedDegrees, 0)
    }

    func testFastCrossingRearmsWhenAlreadyOutsideOuterWindow() {
        var detector = AngleLandmarkDetector(cues: [.init(signedDegrees: 30)])
        detector.update(relativeDegrees: 0)
        XCTAssertEqual(detector.update(relativeDegrees: 60)?.signedDegrees, 30)
        XCTAssertEqual(detector.update(relativeDegrees: 0)?.signedDegrees, 30)
        XCTAssertNil(detector.update(relativeDegrees: 0))
    }

    func testWrapBoundaryDoesNotCrossFrontAngles() {
        var detector = AngleLandmarkDetector()
        XCTAssertNil(detector.update(relativeDegrees: 170))
        XCTAssertEqual(detector.update(relativeDegrees: 179)?.signedDegrees, 180)
        XCTAssertNil(detector.update(relativeDegrees: -179))
        XCTAssertNil(detector.update(relativeDegrees: -170))
        XCTAssertEqual(detector.update(relativeDegrees: -80)?.signedDegrees, -90)
        XCTAssertNil(detector.update(relativeDegrees: -79))
        XCTAssertEqual(detector.update(relativeDegrees: -20)?.signedDegrees, -30)
    }

    func testFullTurnCanReachSameDirectionAgain() {
        var detector = AngleLandmarkDetector(cues: [.init(signedDegrees: 30)])
        detector.update(relativeDegrees: 0)
        XCTAssertEqual(detector.update(relativeDegrees: 30)?.signedDegrees, 30)
        for angle in [90.0, 179, -90, 0] {
            XCTAssertNil(detector.update(relativeDegrees: angle))
        }
        XCTAssertEqual(detector.update(relativeDegrees: 30)?.signedDegrees, 30)
    }

    func testResetClearsLatchesAndInterpolation() {
        var detector = AngleLandmarkDetector()
        XCTAssertEqual(detector.update(relativeDegrees: 30)?.signedDegrees, 30)
        XCTAssertNil(detector.update(relativeDegrees: 30))
        detector.reset()
        XCTAssertEqual(detector.update(relativeDegrees: 30)?.signedDegrees, 30)
        detector.reset()
        XCTAssertNil(detector.update(relativeDegrees: -100))
    }

    func testInvalidReadingBreaksInterpolationWithoutReplayingLatchedCue() {
        var detector = AngleLandmarkDetector(cues: [.init(signedDegrees: 30)])
        detector.update(relativeDegrees: 0)
        XCTAssertNil(detector.update(relativeDegrees: .nan))
        XCTAssertNil(detector.update(relativeDegrees: 60))
        XCTAssertEqual(detector.update(relativeDegrees: 30)?.signedDegrees, 30)
        XCTAssertNil(detector.update(relativeDegrees: .infinity))
        XCTAssertNil(detector.update(relativeDegrees: 30))
    }

    func testSelectionChangesCannotReplayOldCrossing() {
        var detector = AngleLandmarkDetector(cues: [])
        detector.update(relativeDegrees: 0)
        detector.setCues([.init(signedDegrees: 30)])
        XCTAssertNil(detector.update(relativeDegrees: 60))
        XCTAssertEqual(detector.update(relativeDegrees: 30)?.signedDegrees, 30)
        detector.setCues([])
        XCTAssertNil(detector.update(relativeDegrees: 30))
    }

    func testInvalidCueAndToleranceInputsAreSafe() {
        XCTAssertEqual(AngleCue(signedDegrees: .min).label, "유효하지 않은 각도")
        XCTAssertGreaterThan(AngleCue(signedDegrees: .min).magnitudeDegrees, 0)
        let detector = AngleLandmarkDetector(
            cues: [-180, 0, 180, Int.min, Int.max, 30, 30].map(AngleCue.init),
            entryToleranceDegrees: .nan,
            rearmToleranceDegrees: -1
        )
        XCTAssertEqual(detector.cues.map(\.signedDegrees), [0, 30, 180])
        XCTAssertEqual(detector.entryToleranceDegrees, 3)
        XCTAssertEqual(detector.rearmToleranceDegrees, 6)
    }
}


final class ClockDirectionTests: XCTestCase {
    func testEveryLandmarkMapsToClockInBothTurnDirections() {
        for (index, angle) in DirectionReference.signedLandmarks.enumerated() {
            let hour = index == 0 ? 12 : index
            XCTAssertEqual(DirectionReference.nearestHour(Double(angle)), hour)
            XCTAssertEqual(DirectionReference.nearestHour(Double(angle) - 360), hour)
            XCTAssertEqual(DirectionReference.nearestHour(Double(angle) + 720), hour)
        }
        XCTAssertEqual(DirectionReference.nearestHour(-14), 12)
        XCTAssertEqual(DirectionReference.nearestHour(-16), 11)
        XCTAssertEqual(DirectionReference.nearestHour(14), 12)
        XCTAssertEqual(DirectionReference.nearestHour(16), 1)
        XCTAssertEqual(DirectionReference.nearestHour(-180), 6)
        XCTAssertNil(DirectionReference.nearestHour(.nan))
        XCTAssertNil(DirectionReference.landmark(45))
        XCTAssertNil(DirectionReference.landmark(.infinity))
        XCTAssertEqual(DirectionReference.landmark(-180), 180)
    }

    func testClockwiseAndCounterclockwiseFullTurnsEmitEachLandmarkOnce() {
        for sign in [1, -1] {
            var detector = AngleLandmarkDetector()
            // The app consumes the initial front event when reset is announced.
            _ = detector.update(relativeDegrees: 0)
            var events: [Int] = []
            for step in 1...720 {
                if let cue = detector.update(relativeDegrees: Double(step * sign)) {
                    events.append(cue.signedDegrees)
                }
            }
            let clockwise = [30, 60, 90, 120, 150, 180, -150, -120, -90, -60, -30, 0]
            let counterclockwise = [-30, -60, -90, -120, -150, 180, 150, 120, 90, 60, 30, 0]
            XCTAssertEqual(events, (sign == 1 ? clockwise : counterclockwise) + (sign == 1 ? clockwise : counterclockwise))
        }
    }

    func testFrontAndRearHysteresisDoNotChatterAcrossWrap() {
        var detector = AngleLandmarkDetector()
        XCTAssertEqual(detector.update(relativeDegrees: 0)?.id, 0)
        for value in [1.0, -1, 3, -3, 5, -5, 0] {
            XCTAssertNil(detector.update(relativeDegrees: value))
        }
        _ = detector.update(relativeDegrees: 10)
        XCTAssertEqual(detector.update(relativeDegrees: 2)?.id, 0)
        detector.reset()
        XCTAssertEqual(detector.update(relativeDegrees: 180)?.id, 180)
        for value in [-179.0, 179, -180, 176, -176, 180] {
            XCTAssertNil(detector.update(relativeDegrees: value))
        }
        _ = detector.update(relativeDegrees: 170)
        XCTAssertEqual(detector.update(relativeDegrees: -179)?.id, 180)
    }

    func testDisablingFrontAndRearLeavesOtherLandmarksWorking() {
        var detector = AngleLandmarkDetector(cues: AngleCue.defaults.filter { $0.id != 0 && $0.id != 180 })
        XCTAssertNil(detector.update(relativeDegrees: 0))
        XCTAssertEqual(detector.update(relativeDegrees: 30)?.id, 30)
        detector.reset()
        XCTAssertNil(detector.update(relativeDegrees: 180))
        XCTAssertEqual(detector.update(relativeDegrees: -150)?.id, -150)
    }
}
