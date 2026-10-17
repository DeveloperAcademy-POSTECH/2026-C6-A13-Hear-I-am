import XCTest
@testable import HearIAmCore

final class BackEdgeGuideTests: XCTestCase {
    func testCurrentCaptureOrderGuidesFromE4ToE3WithoutMeasuringE3() throws {
        var draft=PreparationDraft()
        let corners=[Point3(6,0,0),Point3(0,0,0),Point3(0,0,4),Point3(6,0,4)]
        XCTAssertEqual(PreparationDraft.captureOrder,[1,0,3,2])
        for index in PreparationDraft.captureOrder.prefix(3) { try draft.captureCorner(index,at:corners[index]) }
        let front=try FrontEdgeGuide(frontLeft:draft.corners[0]!,frontRight:draft.corners[1]!)
        let back=try BackEdgeGuide(front:front,backLeft:draft.corners[3]!)
        XCTAssertEqual(back.start,corners[3]);XCTAssertEqual(back.end,corners[2])
        XCTAssertNil(draft.corners[2]);XCTAssertNil(draft.area)
        try draft.captureCorner(2,at:corners[2])
        XCTAssertEqual(draft.area?.width,6);XCTAssertEqual(draft.area?.depth,4)
    }
    func testRotatedTranslatedStageAndEditedThirdCorner() throws {
        let front=try FrontEdgeGuide(frontLeft:.init(2,1,3),frontRight:.init(2,1,7))
        let back=try BackEdgeGuide(front:front,backLeft:.init(6,1,3))
        XCTAssertEqual(back.end,.init(6,1,7))
        let dx=back.end.x-back.start.x, dz=back.end.z-back.start.z
        let inwardX=front.leftEnd.x-front.leftStart.x, inwardZ=front.leftEnd.z-front.leftStart.z
        XCTAssertEqual(dx*inwardX+dz*inwardZ,0,accuracy:1e-8)
        XCTAssertEqual(hypot(dx,dz),4,accuracy:1e-8)
        let edited=try BackEdgeGuide(front:front,backLeft:.init(7,1,3))
        XCTAssertEqual(edited.end,.init(7,1,7))
    }
    func testInvalidBackCornerRejectedWithoutChangingDraft() throws {
        var draft=PreparationDraft()
        try draft.captureCorner(1,at:.init(0,0,0))
        try draft.captureCorner(0,at:.init(6,0,0))
        try draft.captureCorner(3,at:.init(6,0,4))
        for point in [Point3(6,0,-1),.init(6,0,0.49),.init(6,0.3,4),.init(.nan,0,4)] {
            XCTAssertThrowsError(try draft.captureCorner(3,at:point))
            XCTAssertEqual(draft.corners[3],.init(6,0,4))
        }
        XCTAssertThrowsError(try draft.captureCorner(4,at:.init(0,0,0)))
        XCTAssertThrowsError(try draft.captureCorner(0,at:.init(0.1,0,0)))
        XCTAssertEqual(draft.corners[0],.init(6,0,0))
    }
    func testCameraPitchThresholdAndInvalidVectorsAreDistinct() throws {
        let frame=try StageFrame(origin:.init(0,0,0),front:.init(0,0,-1))
        for pitch in [-90.0,-76,76,90] {
            let r=pitch * .pi/180, v=Point3(0,sin(r),-cos(r))
            XCTAssertNotNil(StageFrame.horizontalForwardRatio(v))
            XCTAssertNil(frame.heading(cameraForward:v))
        }
        for pitch in [-75.0,-45,0,45,75] {
            let r=pitch * .pi/180
            XCTAssertEqual(try XCTUnwrap(frame.heading(cameraForward:.init(0,sin(r),-cos(r)))),0,accuracy:1e-8)
        }
        for invalid in [Point3(0,0,0),.init(.nan,0,0),.init(.infinity,0,0)] {
            XCTAssertNil(StageFrame.horizontalForwardRatio(invalid))
            XCTAssertNil(frame.heading(cameraForward:invalid))
        }
    }
}
