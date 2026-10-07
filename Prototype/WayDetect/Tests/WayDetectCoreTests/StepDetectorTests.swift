import XCTest
@testable import WayDetectCore

final class StepDetectorTests: XCTestCase {
    private func gait(period: Double, cycles: Int, amplitude: Double = 0.2, rate: Double = 0) -> [Double] {
        var detector = StepDetector(), result: [Double] = []
        for i in 0..<Int(period * Double(cycles) * 50) {
            let time = Double(i) / 50, a = sin(time * 2 * .pi / period) * amplitude
            result += detector.receive(MotionObservation(time: time, heading: 0, rotationRate: rate,
                acceleration: abs(a), verticalAcceleration: a))
        }
        return result
    }
    func testWalkingCadenceAcrossSlowAndFastWalking() {
        for period in [0.4, 0.6, 0.9, 1.3] {
            let steps = gait(period: period, cycles: 20)
            XCTAssertEqual(steps.count, 20, "period \(period)")
            XCTAssertEqual(Set(steps).count, steps.count)
        }
    }
    func testStationaryNoiseAndIsolatedBumpAreRejected() {
        XCTAssertEqual(gait(period: 0.6, cycles: 20, amplitude: 0.025).count, 0)
        XCTAssertEqual(gait(period: 0.6, cycles: 1).count, 0)
        XCTAssertEqual(gait(period: 2.2, cycles: 5).count, 0)
    }
    func testRapidTurnIsNotCountedAsGait() {
        XCTAssertEqual(gait(period: 0.6, cycles: 20, rate: 130).count, 0)
    }
    func testSampleGapAndInvalidPostureResetCadence() {
        var detector = StepDetector()
        var steps: [Double] = []
        for cycle in 0..<3 {
            for i in 0..<30 {
                let t = Double(cycle) * 3 + Double(i) / 50
                let a = sin(Double(i) / 30 * 2 * .pi) * 0.2
                steps += detector.receive(.init(time: t, heading: 0, acceleration: abs(a), verticalAcceleration: a))
            }
        }
        XCTAssertEqual(steps.count, 0)
        XCTAssertEqual(detector.receive(.init(time: 10, heading: .nan)), [])
    }
    func testCumulativeIOSUpdatesAreNotSummed() {
        var counter = PedometerCounter()
        XCTAssertTrue(counter.merge(0)); XCTAssertTrue(counter.merge(12)); XCTAssertTrue(counter.merge(12))
        XCTAssertFalse(counter.merge(5)); XCTAssertFalse(counter.merge(-1))
        XCTAssertEqual(counter.total, 12)
        XCTAssertTrue(counter.merge(18)); XCTAssertEqual(counter.total, 18)
    }
}
