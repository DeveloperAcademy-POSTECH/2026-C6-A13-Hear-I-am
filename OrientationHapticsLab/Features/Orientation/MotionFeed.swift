import CoreMotion
import Foundation
import OrientationCore

struct HeadingSample: Sendable {
    let heading: Double?
    let timestamp: TimeInterval
    let receivedAt: Date
}

@MainActor
protocol HeadingFeed: AnyObject {
    func start(onSample: @escaping @MainActor (HeadingSample) -> Void,
               onError: @escaping @MainActor (String) -> Void)
    func stop()
}

@MainActor
final class MotionFeed: HeadingFeed {
    enum Event: Sendable { case sample(HeadingSample), error(String) }
    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "OrientationHapticsLab.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private var delivery: Task<Void, Never>?
    private var continuation: AsyncStream<Event>.Continuation?

    func start(onSample: @escaping @MainActor (HeadingSample) -> Void,
               onError: @escaping @MainActor (String) -> Void) {
        stop()
        guard manager.isDeviceMotionAvailable,
              CMMotionManager.availableAttitudeReferenceFrames().contains(.xArbitraryZVertical) else {
            onError("이 기기에서 방향 센서를 사용할 수 없어요.")
            return
        }
        // A busy UI receives the newest sample, not a backlog of obsolete 60 Hz callbacks.
        let channel = AsyncStream<Event>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation = channel.continuation
        delivery = Task {
            for await event in channel.stream {
                guard !Task.isCancelled else { break }
                switch event {
                case .sample(let sample): onSample(sample)
                case .error(let message): onError(message)
                }
            }
        }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue,
                                         withHandler: Self.makeHandler(for: channel.continuation))
    }

    /// The Objective-C callback is not Sendable in the SDK. Creating it inside start()
    /// would inherit MainActor even though Core Motion calls it on the supplied queue.
    nonisolated static func makeHandler(for continuation: AsyncStream<Event>.Continuation)
        -> @Sendable (CMDeviceMotion?, (any Error)?) -> Void {
        { data, error in
            if let error { continuation.yield(.error(error.localizedDescription)); return }
            guard let data else { return }
            let r = data.attitude.rotationMatrix
            let matrix = ReferenceToDeviceRotationMatrix(
                m11: r.m11, m12: r.m12, m13: r.m13,
                m21: r.m21, m22: r.m22, m23: r.m23,
                m31: r.m31, m32: r.m32, m33: r.m33)
            continuation.yield(.sample(HeadingSample(
                heading: HeadingMath.screenOutwardHeadingDegrees(referenceToDevice: matrix),
                timestamp: data.timestamp, receivedAt: Date())))
        }
    }

    func stop() {
        delivery?.cancel()
        delivery = nil
        continuation?.finish()
        continuation = nil
        manager.stopDeviceMotionUpdates()
    }
}
