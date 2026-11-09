import XCTest
@testable import HearIAmCore

final class WalkGlowDirectionTests: XCTestCase {
    /// Facing the point holds the light in the middle through sway that 정면 찾기 would also ignore.
    func testAlignedHoldsUntilTheBodyTurnsClearlyAway() {
        var glow = WalkGlowDirection()
        glow.update(bearing: 60, time: 0)
        XCTAssertEqual(glow.phase, .finding)
        glow.update(bearing: 10, time: 0.1)
        XCTAssertEqual(glow.phase, .aligned)
        for (i, b) in [25.0, -30, 35, -40].enumerated() {
            glow.update(bearing: b, time: 0.2 + Double(i) * 0.1)
            XCTAssertEqual(glow.phase, .aligned, "\(b)° is within the departure angle")
        }
        glow.update(bearing: 50, time: 1)
        XCTAssertEqual(glow.phase, .finding)
        XCTAssertEqual(glow.bearing, 50)
    }
    func testMissingPoseClearsTheBearingButKeepsThePhase() {
        var glow = WalkGlowDirection()
        glow.update(bearing: 5, time: 0)
        glow.update(bearing: nil, time: 0.1)
        XCTAssertNil(glow.bearing)
        XCTAssertEqual(glow.phase, .aligned)
        glow.reset()
        XCTAssertEqual(glow.phase, .finding)
    }
    func testDepartureMatchesFrontFinding() {
        XCTAssertEqual(WalkGlowDirection().departureDegrees, FrontDirectionPractice().departureDegrees)
    }
}
