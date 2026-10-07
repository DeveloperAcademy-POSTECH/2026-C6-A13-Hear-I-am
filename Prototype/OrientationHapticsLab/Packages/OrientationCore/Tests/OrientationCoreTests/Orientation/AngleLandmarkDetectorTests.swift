import XCTest
@testable import OrientationCore

final class AngleLandmarkDetectorTests: XCTestCase {
    func testDefaultLeftAndRightAnglesAndLabels() throws {
        XCTAssertEqual(AngleCue.defaults.map(\.signedDegrees), [-90, -45, -30, 30, 45, 90])
        XCTAssertEqual(AngleCue(signedDegrees: -30).label, "왼쪽 30°")
        XCTAssertEqual(AngleCue(signedDegrees: 45).label, "오른쪽 45°")
        let cue = AngleCue(signedDegrees: -90)
        XCTAssertEqual(try JSONDecoder().decode(AngleCue.self, from: JSONEncoder().encode(cue)), cue)
        for angle in [-90, -45, -30, 30, 45, 90] {
            var detector = AngleLandmarkDetector()
            detector.update(relativeDegrees: 0)
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
        XCTAssertNil(detector.update(relativeDegrees: 0))
        XCTAssertEqual(detector.update(relativeDegrees: 80)?.signedDegrees, 45)
        XCTAssertNil(detector.update(relativeDegrees: 81))
        XCTAssertNil(detector.update(relativeDegrees: 82))
        // The return path crosses 45° first, then 30°; the newer 30° cue wins.
        XCTAssertEqual(detector.update(relativeDegrees: 0)?.signedDegrees, 30)
        XCTAssertNil(detector.update(relativeDegrees: 0))
        XCTAssertEqual(detector.update(relativeDegrees: -100)?.signedDegrees, -90)
        XCTAssertNil(detector.update(relativeDegrees: -101))
        XCTAssertEqual(detector.update(relativeDegrees: 0)?.signedDegrees, -30)
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
        XCTAssertNil(detector.update(relativeDegrees: 179))
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
        XCTAssertEqual(detector.cues.map(\.signedDegrees), [30])
        XCTAssertEqual(detector.entryToleranceDegrees, 3)
        XCTAssertEqual(detector.rearmToleranceDegrees, 6)
    }
}
