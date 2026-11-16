import XCTest
@testable import HearIAmCore

/// Carried over from PoC1's AngleLandmarkDetectorTests with integer landmarks.
final class LandmarkDetectorTests: XCTestCase {
    /// PoC1's original 30° landmarks; the detector logic is the same for any spacing.
    let poc1=[0,30,60,90,120,150,180,-150,-120,-90,-60,-30]
    func testEveryLandmarkFiresWhenReached() {
        for angle in DirectionPattern.landmarks {
            var d=LandmarkDetector()
            d.update(relativeDegrees:Double(angle)-10)
            XCTAssertEqual(d.update(relativeDegrees:Double(angle)),angle)
        }
    }
    func testEntryHysteresisAndExactThresholds() {
        var d=LandmarkDetector(landmarks:[30])
        XCTAssertNil(d.update(relativeDegrees:26.9))
        XCTAssertEqual(d.update(relativeDegrees:27),30)
        for angle in [29.0,30,32,34,35.9,36,31,27] { XCTAssertNil(d.update(relativeDegrees:angle),"\(angle)") }
        XCTAssertNil(d.update(relativeDegrees:23.9))
        XCTAssertNil(d.update(relativeDegrees:26.9))
        XCTAssertEqual(d.update(relativeDegrees:27),30)
    }
    func testCrossingOutsideWindowStillFiresAndDoesNotQueueOlderLandmarks() {
        var d=LandmarkDetector(landmarks:poc1)
        XCTAssertEqual(d.update(relativeDegrees:0),0)
        XCTAssertEqual(d.update(relativeDegrees:80),60)
        XCTAssertNil(d.update(relativeDegrees:81))
        XCTAssertEqual(d.update(relativeDegrees:0),0)
        XCTAssertNil(d.update(relativeDegrees:0))
        XCTAssertEqual(d.update(relativeDegrees:-100),-90)
        XCTAssertEqual(d.update(relativeDegrees:0),0)
    }
    func testWrapBoundaryDoesNotCrossFrontLandmarks() {
        var d=LandmarkDetector(landmarks:poc1)
        XCTAssertNil(d.update(relativeDegrees:170))
        XCTAssertEqual(d.update(relativeDegrees:179),180)
        XCTAssertNil(d.update(relativeDegrees:-179))
        XCTAssertNil(d.update(relativeDegrees:-170))
        XCTAssertEqual(d.update(relativeDegrees:-80),-90)
        XCTAssertEqual(d.update(relativeDegrees:-20),-30)
    }
    func testFullTurnReachesTheSameLandmarkAgain() {
        var d=LandmarkDetector(landmarks:[30])
        d.update(relativeDegrees:0)
        XCTAssertEqual(d.update(relativeDegrees:30),30)
        for angle in [90.0,179,-90,0] { XCTAssertNil(d.update(relativeDegrees:angle)) }
        XCTAssertEqual(d.update(relativeDegrees:30),30)
    }
    func testResetAndInvalidReadings() {
        var d=LandmarkDetector(landmarks:[30])
        d.update(relativeDegrees:0)
        XCTAssertNil(d.update(relativeDegrees:.nan))
        XCTAssertNil(d.update(relativeDegrees:60))
        XCTAssertEqual(d.update(relativeDegrees:30),30)
        XCTAssertNil(d.update(relativeDegrees:30))
        d.reset()
        XCTAssertEqual(d.update(relativeDegrees:30),30)
    }
    func testDefaultUsesThe45DegreeFieldLandmarks() {
        var d=LandmarkDetector()
        XCTAssertEqual(d.landmarks,[-135,-90,-45,0,45,90,135,180])
        d.update(relativeDegrees:0)
        XCTAssertNil(d.update(relativeDegrees:30))
        XCTAssertEqual(d.update(relativeDegrees:44),45)
        XCTAssertEqual(d.update(relativeDegrees:100),90)
    }
    func testInvalidInputsAreSafe() {
        let d=LandmarkDetector(landmarks:[-180,0,180,Int.min,Int.max,30,30],entryTolerance:.nan,rearmTolerance:-1)
        XCTAssertEqual(d.landmarks,[0,30,180])
        XCTAssertEqual(d.entryTolerance,3);XCTAssertEqual(d.rearmTolerance,6)
    }
    func testHeadingMath() {
        XCTAssertEqual(HeadingMath.wrapDegrees(190),-170)
        XCTAssertEqual(HeadingMath.signedDeltaDegrees(from:170,to:-170),20)
        XCTAssertTrue(HeadingMath.wrapDegrees(.infinity).isNaN)
        // Phone upright facing reference +X: screen normal (1,0,0) → heading 0. Turned right 90° → +90.
        let facingX=ReferenceToDeviceRotation(m11:0,m12:0,m13:-1,m21:0,m22:1,m23:0,m31:1,m32:0,m33:0)
        XCTAssertEqual(HeadingMath.screenHeadingDegrees(facingX)!,0,accuracy:1e-9)
        let facingMinusY=ReferenceToDeviceRotation(m11:0,m12:0,m13:1,m21:-1,m22:0,m23:0,m31:0,m32:-1,m33:0)
        XCTAssertEqual(HeadingMath.screenHeadingDegrees(facingMinusY)!,90,accuracy:1e-9)
        let flat=ReferenceToDeviceRotation(m11:1,m12:0,m13:0,m21:0,m22:1,m23:0,m31:0,m32:0,m33:1)
        XCTAssertNil(HeadingMath.screenHeadingDegrees(flat))
    }
    /// 10/19: walking straight sways the body by more than 6°, so 「앞」 repeated every 1–2 s.
    func testFrontFiresAgainOnlyAfterLeavingTwentyDegrees() {
        var d=LandmarkDetector()
        XCTAssertEqual(d.update(relativeDegrees:0),0)
        for angle in [8.0,-12,19,-19.9,4,0] { XCTAssertNil(d.update(relativeDegrees:angle),"\(angle)") }
        XCTAssertNil(d.update(relativeDegrees:21))
        XCTAssertEqual(d.update(relativeDegrees:2),0)
        // Other landmarks keep the ±6° rearm.
        XCTAssertEqual(d.update(relativeDegrees:45),45)
        XCTAssertNil(d.update(relativeDegrees:37))
        XCTAssertEqual(d.update(relativeDegrees:44),45)
    }
}
