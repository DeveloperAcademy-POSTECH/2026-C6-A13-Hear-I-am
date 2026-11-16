import XCTest
@testable import HearIAmCore

final class GuidanceWalkTimelineTests: XCTestCase {
    private func sample(_ t: Double, _ x: Double?, status: GuidanceReplayStatus = .guiding) -> GuidanceReplaySample {
        .init(time: t, position: x.map { FloorPoint($0, 0) }, heading: x == nil ? nil : 0,
              targetIndex: 1, status: x == nil ? .untracked : status)
    }
    func testDistanceDrivesGaitIndependentlyOfSeekOrderAndPlaybackRate() {
        let samples = (0...20).map { sample(Double($0) * 0.2, Double($0) * 0.2) }
        let timeline = GuidanceWalkTimeline(replay: .init(duration: 4, samples: samples))
        let atOne = timeline.pose(at: 1)
        XCTAssertEqual(atOne.distance, 1, accuracy: 1e-8)
        XCTAssertEqual(atOne.speed, 1, accuracy: 1e-8)
        XCTAssertEqual(atOne.blend, 1)
        for t in [3.8, 0.0, 2.5, 1.0, 1.0] { _ = timeline.pose(at: t) }
        XCTAssertEqual(atOne, timeline.pose(at: 1), "Seeking backward and pausing must not accumulate gait phase")
        XCTAssertEqual(timeline.pose(at: 2).distance, 2 * atOne.distance, accuracy: 1e-8)
        XCTAssertEqual(timeline.pose(at: 4).blend, 0, "End in a resting pose")
    }
    func testRecordedStopsRestButPausedGuidanceCanStillContainRealMovement() {
        let samples = (0...30).map { i in
            let t = Double(i) * 0.2
            return sample(t, t <= 2 ? t : t <= 4 ? 2 : t - 2, status: .paused)
        }
        let timeline = GuidanceWalkTimeline(replay: .init(duration: 6, samples: samples))
        XCTAssertEqual(timeline.pose(at: 1).blend, 1, "Observed motion matters, not guidance status")
        XCTAssertEqual(timeline.pose(at: 3).speed, 0)
        XCTAssertEqual(timeline.pose(at: 3).blend, 0)
        XCTAssertEqual(timeline.pose(at: 2.5).distance, timeline.pose(at: 3.5).distance)
        XCTAssertEqual(timeline.pose(at: 5).blend, 1)
        XCTAssertGreaterThan(timeline.pose(at: 5).distance, timeline.pose(at: 3).distance)
    }
    func testJitterDoesNotTriggerWalkingButSlowIntentionalMotionDoes() {
        let jitter = (0...20).map { sample(Double($0) * 0.2, $0.isMultiple(of: 2) ? 0 : 0.005) }
        let stationary = GuidanceWalkTimeline(replay: .init(duration: 4, samples: jitter))
        XCTAssertEqual(stationary.pose(at: 2).distance, 0)
        XCTAssertEqual(stationary.pose(at: 2).blend, 0)
        let slow = (0...20).map { sample(Double($0) * 0.2, Double($0) * 0.03) }
        let moving = GuidanceWalkTimeline(replay: .init(duration: 4, samples: slow))
        XCTAssertEqual(moving.pose(at: 2).distance, 0.3, accuracy: 1e-8)
        XCTAssertEqual(moving.pose(at: 2).blend, 1, accuracy: 1e-8)
        XCTAssertLessThan(moving.pose(at: 2).strideScale, 0.25, "Slow walking uses short steps")
        XCTAssertGreaterThan(moving.pose(at: 2).gaitDistance, moving.pose(at: 2).distance * 4, "A short stride should not become a slow-motion long stride")
    }
    func testMissingTrackingAndTeleportsNeverAddFictitiousSteps() {
        let samples = [sample(0, 0), sample(0.2, 0.2), sample(0.4, nil), sample(2, 8),
                       sample(2.2, 8.2), sample(2.4, 25), sample(2.6, 25.2)]
        let timeline = GuidanceWalkTimeline(replay: .init(duration: 2.6, samples: samples))
        XCTAssertEqual(timeline.pose(at: 1).blend, 0)
        XCTAssertEqual(timeline.pose(at: 2.3).blend, 0)
        XCTAssertEqual(timeline.pose(at: 2.6).distance, 0.6, accuracy: 1e-8)
        XCTAssertEqual(timeline.pose(at: .nan).blend, 0)
    }
}
