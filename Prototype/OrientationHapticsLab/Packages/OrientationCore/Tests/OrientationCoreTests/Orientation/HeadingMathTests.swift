import XCTest
@testable import OrientationCore

final class HeadingMathTests: XCTestCase {
    func testPortraitFacingAndRightPositiveSignWithLeanAndRoll() throws {
        // Build each pose from physical device axes in a Z-up world, independently of
        // the extraction routine. Portrait top points up; outward display normal faces
        // world +X at zero. A physical right turn rotates clockwise around world +Z.
        for heading in [-170.0, -90, -45, -30, 0, 30, 45, 90, 170] {
            for lean in [-40.0, -15, 0, 15, 40] {
                for roll in [-25.0, 0, 25] {
                    let value = try XCTUnwrap(HeadingMath.screenOutwardHeadingDegrees(
                        referenceToDevice: portraitPose(rightTurn: heading, lean: lean, roll: roll)
                    ))
                    XCTAssertEqual(value, heading, accuracy: 0.000_001,
                                   "heading=\(heading), lean=\(lean), roll=\(roll)")
                }
            }
        }
    }

    func testRejectsNearVerticalScreenNormal() {
        XCTAssertNil(HeadingMath.screenOutwardHeadingDegrees(
            referenceToDevice: portraitPose(rightTurn: 45, lean: 89, roll: 0)
        ))
        XCTAssertNil(HeadingMath.screenOutwardHeadingDegrees(
            referenceToDevice: portraitPose(rightTurn: 45, lean: -89, roll: 0)
        ))
        XCTAssertNotNil(HeadingMath.screenOutwardHeadingDegrees(
            referenceToDevice: portraitPose(rightTurn: 45, lean: 70, roll: 0)
        ))
    }

    func testRejectsInvalidRotationsAndConfiguration() {
        let zero = ReferenceToDeviceRotationMatrix(
            m11: 0, m12: 0, m13: 0, m21: 0, m22: 0, m23: 0, m31: 0, m32: 0, m33: 0
        )
        let nonfinite = ReferenceToDeviceRotationMatrix(
            m11: .nan, m12: 1, m13: 0, m21: 0, m22: 0, m23: 1, m31: 1, m32: 0, m33: 0
        )
        let nonorthogonal = ReferenceToDeviceRotationMatrix(
            m11: 1, m12: 0, m13: 0, m21: 0, m22: 0, m23: 1, m31: 1, m32: 0, m33: 0
        )
        let reflected = ReferenceToDeviceRotationMatrix(
            m11: 0, m12: -1, m13: 0, m21: 0, m22: 0, m23: 1, m31: 1, m32: 0, m33: 0
        )
        for matrix in [zero, nonfinite, nonorthogonal, reflected] {
            XCTAssertNil(HeadingMath.screenOutwardHeadingDegrees(referenceToDevice: matrix))
        }
        let valid = portraitPose(rightTurn: 0, lean: 0, roll: 0)
        for threshold in [0, -1, 1.1, Double.nan, .infinity] {
            XCTAssertNil(HeadingMath.screenOutwardHeadingDegrees(
                referenceToDevice: valid, minimumHorizontalFraction: threshold
            ))
        }
    }

    func testWrapAndShortestSignedChanges() {
        for (input, expected) in [
            (0.0, 0.0), (360, 0), (-720, 0), (180, 180), (-180, -180),
            (540, 180), (-540, -180), (181, -179), (-181, 179)
        ] {
            XCTAssertEqual(HeadingMath.wrapDegrees(input), expected, accuracy: 0.000_001)
        }
        XCTAssertEqual(HeadingMath.signedDeltaDegrees(from: 179, to: -179), 2)
        XCTAssertEqual(HeadingMath.signedDeltaDegrees(from: -179, to: 179), -2)
        XCTAssertTrue(HeadingMath.wrapDegrees(.infinity).isNaN)
        XCTAssertTrue(HeadingMath.signedDeltaDegrees(from: .nan, to: 0).isNaN)
    }

    func testRelativeResetAndContinuousFullTurns() throws {
        var tracker = RelativeHeadingTracker()
        XCTAssertNil(tracker.update(absoluteHeadingDegrees: 30))
        XCTAssertEqual(tracker.reset(absoluteHeadingDegrees: 0)?.relativeDegrees, 0)
        for absolute in [90.0, 179, -90, 0] {
            _ = tracker.update(absoluteHeadingDegrees: absolute)
        }
        let right = try XCTUnwrap(tracker.reading)
        XCTAssertEqual(right.relativeDegrees, 0)
        XCTAssertEqual(right.continuousDegrees, 360)

        tracker.reset(absoluteHeadingDegrees: 0)
        for absolute in [-90.0, -179, 90, 0] {
            _ = tracker.update(absoluteHeadingDegrees: absolute)
        }
        XCTAssertEqual(tracker.reading?.continuousDegrees, -360)
        tracker.reset(absoluteHeadingDegrees: 170)
        XCTAssertEqual(tracker.update(absoluteHeadingDegrees: -160)?.relativeDegrees, 30)
        XCTAssertEqual(tracker.update(absoluteHeadingDegrees: 140)?.relativeDegrees, -30)
    }

    func testResetAcrossWrapAndInvalidSamplesCannotCorruptCycle() {
        var tracker = RelativeHeadingTracker()
        tracker.reset(absoluteHeadingDegrees: 170)
        XCTAssertEqual(tracker.update(absoluteHeadingDegrees: 179)?.continuousDegrees, 9)
        XCTAssertEqual(tracker.update(absoluteHeadingDegrees: -179)?.continuousDegrees, 11)
        let before = tracker.reading
        XCTAssertNil(tracker.reset(absoluteHeadingDegrees: .nan))
        XCTAssertNil(tracker.update(absoluteHeadingDegrees: .infinity))
        XCTAssertEqual(tracker.reading, before)
        XCTAssertEqual(tracker.baselineHeadingDegrees, 170)
        XCTAssertEqual(tracker.reset(absoluteHeadingDegrees: -179)?.continuousDegrees, 0)
        XCTAssertEqual(tracker.update(absoluteHeadingDegrees: 179)?.relativeDegrees, -2)
        tracker.clear()
        XCTAssertNil(tracker.baselineHeadingDegrees)
        XCTAssertNil(tracker.reading)
        XCTAssertNil(tracker.update(absoluteHeadingDegrees: 30))
    }

    private func portraitPose(rightTurn: Double, lean: Double, roll: Double) -> ReferenceToDeviceRotationMatrix {
        let h = rightTurn * .pi / 180
        let p = lean * .pi / 180
        let r = roll * .pi / 180
        let right = [sin(h), cos(h), 0]
        let top = [-cos(h) * sin(p), sin(h) * sin(p), cos(p)]
        let outward = [cos(h) * cos(p), -sin(h) * cos(p), sin(p)]
        let rolledRight = zip(right, top).map { cos(r) * $0.0 + sin(r) * $0.1 }
        let rolledTop = zip(right, top).map { -sin(r) * $0.0 + cos(r) * $0.1 }
        return ReferenceToDeviceRotationMatrix(
            m11: rolledRight[0], m12: rolledRight[1], m13: rolledRight[2],
            m21: rolledTop[0], m22: rolledTop[1], m23: rolledTop[2],
            m31: outward[0], m32: outward[1], m33: outward[2]
        )
    }
}
