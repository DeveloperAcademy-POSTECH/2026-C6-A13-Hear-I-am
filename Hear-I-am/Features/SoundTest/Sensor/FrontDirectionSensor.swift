import CoreMotion
import HearIAmCore

@MainActor protocol FrontDirectionSensing: AnyObject {
    var onSample: ((Double?, TimeInterval) -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    func start()
    func stop()
}

/// Arbitrary, gravity-aligned frame: only relative turns matter, not magnetic north.
@MainActor final class FrontDirectionSensor: FrontDirectionSensing {
    var onSample: ((Double?, TimeInterval) -> Void)?
    var onFailure: ((String) -> Void)?
    private let motion = CMMotionManager()
    private var generation = UUID()

    func start() {
        stop()
        guard motion.isDeviceMotionAvailable,
              CMMotionManager.availableAttitudeReferenceFrames().contains(.xArbitraryZVertical) else {
            onFailure?("이 기기에서는 몸 방향을 확인할 수 없어요. 실제 iPhone에서 연습해주세요.")
            return
        }
        let token = generation
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] sample, error in
            let matrix = sample?.attitude.rotationMatrix
            let time = sample?.timestamp
            let heading = matrix.flatMap { m in
                HeadingMath.screenHeadingDegrees(.init(m11: m.m11, m12: m.m12, m13: m.m13,
                                                       m21: m.m21, m22: m.m22, m23: m.m23,
                                                       m31: m.m31, m32: m.m32, m33: m.m33))
            }
            let failed = error != nil
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if failed {
                    self.stop()
                    self.onFailure?("몸 방향을 확인하지 못했어요. 휴대폰의 움직임 접근 설정과 착용 상태를 확인한 뒤 다시 시도해주세요.")
                } else if let time { self.onSample?(heading, time) }
            }
        }
    }
    func stop() { generation = UUID(); motion.stopDeviceMotionUpdates() }
    deinit { motion.stopDeviceMotionUpdates() }
}
