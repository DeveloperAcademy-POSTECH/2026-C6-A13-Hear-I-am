import XCTest
@testable import HearIAmCore

final class StageHeadingTests: XCTestCase {
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
