import CoreMotion
import OrientationCore
import XCTest
@testable import OrientationHapticsLab

/// Exercise the production SDK callbacks on a foreign queue. Fake HeadingFeed tests
/// bypass this boundary and cannot catch Swift 6 executor assertions on real devices.
@MainActor
final class SensorCallbackIsolationTests: XCTestCase {
    func testMotionCallbackCreatedFromMainActorRunsOnBackgroundQueue() async {
        let channel = AsyncStream<MotionFeed.Event>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let callback = MotionFeed.makeHandler(for: channel.continuation)
        await onBackgroundQueue {
            XCTAssertFalse(Thread.isMainThread)
            callback(nil, NSError(domain: "MotionTest", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "sensor unavailable"]))
            channel.continuation.finish()
        }
        var iterator = channel.stream.makeAsyncIterator()
        guard case .error(let message) = await iterator.next() else {
            XCTFail("The background callback must deliver its error without an executor assertion")
            return
        }
        XCTAssertEqual(message, "sensor unavailable")
    }

    func testMotionCallbackKeepsNewestEventAndIgnoresEmptyReports() async {
        let channel = AsyncStream<MotionFeed.Event>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let callback = MotionFeed.makeHandler(for: channel.continuation)
        await onBackgroundQueue {
            callback(nil, nil)
            for message in ["old", "newest"] {
                callback(nil, NSError(domain: "MotionTest", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: message]))
            }
            channel.continuation.finish()
        }
        var iterator = channel.stream.makeAsyncIterator()
        guard case .error(let message) = await iterator.next() else {
            XCTFail("Expected latest sensor event")
            return
        }
        XCTAssertEqual(message, "newest")
        let extra = await iterator.next()
        XCTAssertNil(extra)
    }

    func testPedometerCallbackRunsOnBackgroundQueueAndPreservesFailure() async {
        let channel = AsyncStream<(WalkingSample?, String?)>.makeStream()
        let callback = PedometerFeed.makeHandler(from: Date()) { sample, message in
            channel.continuation.yield((sample, message))
        }
        await onBackgroundQueue {
            XCTAssertFalse(Thread.isMainThread)
            callback(nil, NSError(domain: "PedometerTest", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "permission denied"]))
            channel.continuation.finish()
        }
        var iterator = channel.stream.makeAsyncIterator()
        let result = await iterator.next()
        XCTAssertNotNil(result)
        XCTAssertNil(result?.0)
        XCTAssertEqual(result?.1, "permission denied")
    }

    private func onBackgroundQueue(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                work()
                done.resume()
            }
        }
    }
}
