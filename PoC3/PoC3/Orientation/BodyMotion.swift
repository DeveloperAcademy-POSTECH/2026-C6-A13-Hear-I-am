import CoreMotion
import Combine
import Foundation

@MainActor
final class BodyMotion: ObservableObject {
    @Published private(set) var heading: Double?
    @Published private(set) var status = "몸 방향 센서 대기"
    private(set) var timestamp = -Double.infinity
    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue(); q.name = "PoC3.body-motion"; q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated; return q
    }()
    private var delivery: Task<Void, Never>?
    private var continuation: AsyncStream<Sample>.Continuation?
    private struct Sample: Sendable {
        let row: [Double]?
        let timestamp: Double
        let error: String?
    }
    func start() {
        stop()
        guard manager.isDeviceMotionAvailable,
              CMMotionManager.availableAttitudeReferenceFrames().contains(.xArbitraryZVertical) else {
            status = "이 기기에서 몸 방향을 측정할 수 없습니다"; return
        }
        let stream = AsyncStream<Sample>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation = stream.continuation
        delivery = Task { [weak self] in
            for await sample in stream.stream {
                guard !Task.isCancelled, let self else { return }
                guard sample.timestamp > self.timestamp else { continue }
                self.timestamp = sample.timestamp
                if let row = sample.row {
                    self.heading = BodyNavigationMath.outwardHeading(m31: row[0], m32: row[1], m33: row[2])
                } else { self.heading = nil }
                self.status = sample.error ?? (self.heading == nil ? "폰을 세로로 고정하고 화면이 바깥쪽을 향하게 해주세요" : "몸 방향 수신 중 · 30Hz")
            }
        }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue,
                                          withHandler: Self.handler(stream.continuation))
    }
    // Created outside MainActor so Core Motion's serial background callback never inherits it.
    nonisolated private static func handler(_ continuation: AsyncStream<Sample>.Continuation)
        -> @Sendable (CMDeviceMotion?, (any Error)?) -> Void {
        { motion, error in
            if let error {
                continuation.yield(Sample(row: nil, timestamp: ProcessInfo.processInfo.systemUptime,
                                           error: error.localizedDescription))
            } else if let motion {
                let r = motion.attitude.rotationMatrix
                continuation.yield(Sample(row: [r.m31, r.m32, r.m33], timestamp: motion.timestamp, error: nil))
            }
        }
    }
    func fresh(at now: Double) -> Bool {
        heading != nil && now >= timestamp && now - timestamp <= 0.5
    }
    func stop() {
        delivery?.cancel(); delivery = nil
        continuation?.finish(); continuation = nil
        manager.stopDeviceMotionUpdates()
        heading = nil; timestamp = -.infinity
    }
}
