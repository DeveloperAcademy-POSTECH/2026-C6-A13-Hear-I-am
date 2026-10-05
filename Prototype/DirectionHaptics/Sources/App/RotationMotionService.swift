import CoreMotion
import Foundation

@MainActor
final class RotationMotionService {
    struct Sample {
        let yaw: Double
        let angularSpeed: Double
        let faceUp: Bool
        let time: Double
    }
    enum MotionError: LocalizedError {
        case unavailable, missing, posture
        var errorDescription: String? {
            switch self {
            case .unavailable: return "회전 센서를 사용할 수 없습니다. 실제 iPhone에서 실행해 주세요."
            case .missing: return "회전 센서 응답이 끊겼습니다. 휴대폰을 든 뒤 다시 시작해 주세요."
            case .posture: return "휴대폰 화면이 위를 향하도록 들고 다시 시작해 주세요."
            }
        }
    }
    private let manager = CMMotionManager()
    private var task: Task<Void, Never>?
    private(set) var latest: Sample?
    private let clock = ContinuousClock()
    private var receivedAt: ContinuousClock.Instant?
    let isPreview: Bool
    private var previewYaw = 0.0

    init(isPreview: Bool) { self.isPreview = isPreview }

    func start(onSample: @escaping (Sample) -> Void, onFailure: @escaping (Error) -> Void) throws {
        // Keep the sensor running across rounds; restarting changes its reference frame.
        guard task == nil else { return }
        guard isPreview || manager.isDeviceMotionAvailable else { throw MotionError.unavailable }
        if !isPreview {
            manager.deviceMotionUpdateInterval = 1.0 / 50
            manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        }
        task = Task { [weak self] in
            let startedAt = ContinuousClock.now
            var lastReceived = startedAt
            var lastTimestamp = -Double.infinity
            while !Task.isCancelled {
                guard let self else { return }
                let now = self.clock.now
                var sample: Sample?
                if self.isPreview {
                    #if DEBUG && targetEnvironment(simulator)
                    let delayed = ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--motion-start-delay")
                    if !delayed || startedAt.duration(to: now) >= .seconds(2) {
                        sample = Sample(yaw: self.previewYaw, angularSpeed: 0, faceUp: true, time: ProcessInfo.processInfo.systemUptime)
                    }
                    #endif
                } else if let data = self.manager.deviceMotion, data.timestamp.isFinite,
                          data.timestamp > lastTimestamp, data.attitude.yaw.isFinite,
                          data.rotationRate.x.isFinite, data.rotationRate.y.isFinite, data.rotationRate.z.isFinite {
                    lastTimestamp = data.timestamp
                    let rate = data.rotationRate
                    sample = Sample(yaw: data.attitude.yaw,
                        angularSpeed: sqrt(rate.x * rate.x + rate.y * rate.y + rate.z * rate.z) * 180 / .pi,
                        faceUp: data.gravity.z < -0.65, time: data.timestamp)
                }
                if let sample {
                    lastReceived = now; self.receivedAt = now; self.latest = sample; onSample(sample)
                } else if lastReceived.duration(to: now) > (self.latest == nil ? .seconds(5) : .seconds(2)) {
                    onFailure(MotionError.missing); return
                }
                do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
            }
        }
    }
    func reference() throws -> Double {
        guard let latest, let receivedAt, receivedAt.duration(to: clock.now) < .milliseconds(300) else { throw MotionError.missing }
        guard latest.faceUp else { throw MotionError.posture }
        return latest.yaw
    }
    func waitForReference() async throws -> Double {
        let deadline = clock.now.advanced(by: .seconds(10))
        while clock.now < deadline {
            try Task.checkCancellation()
            if let value = try? reference() { return value }
            try await Task.sleep(for: .milliseconds(30))
        }
        if latest?.faceUp == false { throw MotionError.posture }
        throw MotionError.missing
    }
    func stop() {
        task?.cancel(); task = nil
        manager.stopDeviceMotionUpdates(); latest = nil; receivedAt = nil
    }
    #if DEBUG && targetEnvironment(simulator)
    func rotatePreview(by degrees: Double) {
        guard isPreview else { return }
        previewYaw -= degrees * .pi / 180
    }
    #endif
}
