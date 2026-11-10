import XCTest
@testable import HearIAmCore

final class WalkGlowDirectionTests: XCTestCase {
    /// The light is centred while the sound is quiet and leaves when the ticks would start again.
    func testAlignedFollowsTheDirectionTicks() {
        var glow = WalkGlowDirection()
        var ticks = DirectionTickGate()
        for (i, b) in [60.0, 10, 25, -32, 34, 20, -45, 5].enumerated() {
            glow.update(bearing: b, time: Double(i) * 0.1)
            _ = ticks.update(time: Double(i) * 0.1, bearing: b)
            XCTAssertEqual(glow.phase == .aligned, ticks.isAligned, "at \(b)°")
        }
    }
    func testArrowIsAheadWhileAlignedAndStepsWithHysteresis() {
        var glow = WalkGlowDirection()
        glow.update(bearing: 50, time: 0)
        XCTAssertEqual(glow.arrowDegrees, 45)
        glow.update(bearing: 75, time: 0.1)
        XCTAssertEqual(glow.arrowDegrees, 45, "75° is not yet clearly past 67.5°")
        glow.update(bearing: 80, time: 0.2)
        XCTAssertEqual(glow.arrowDegrees, 90)
        glow.update(bearing: 10, time: 0.3)
        XCTAssertEqual(glow.phase, .aligned)
        XCTAssertEqual(glow.arrowDegrees, 0)
    }
    /// Behind the body the arrow stays put across ±180° instead of flipping between the two sides.
    func testArrowBehindDoesNotFlipAcrossTheBack() {
        var glow = WalkGlowDirection()
        glow.update(bearing: 178, time: 0)
        XCTAssertEqual(glow.arrowDegrees, 180)
        glow.update(bearing: -176, time: 0.1)
        XCTAssertEqual(glow.arrowDegrees, 180)
    }
    func testMissingPoseClearsTheBearingButKeepsThePhase() {
        var glow = WalkGlowDirection()
        glow.update(bearing: 5, time: 0)
        glow.update(bearing: nil, time: 0.1)
        XCTAssertNil(glow.bearing)
        XCTAssertEqual(glow.phase, .aligned)
        glow.reset()
        XCTAssertEqual(glow.phase, .finding)
        XCTAssertEqual(glow.arrowDegrees, 0)
    }
}
