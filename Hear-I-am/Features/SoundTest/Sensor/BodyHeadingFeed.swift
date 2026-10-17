import CoreMotion
import HearIAmCore

/// Waist-phone heading from Core Motion, as in PoC1. Only changes are meaningful; the zero is arbitrary.
@MainActor final class BodyHeadingFeed {
    private let manager=CMMotionManager()
    private(set) var heading: Double?

    /// Returns an error message when the sensor is unavailable.
    func start(_ onHeading: @escaping (Double?) -> Void) -> String? {
        guard manager.isDeviceMotionAvailable,
              CMMotionManager.availableAttitudeReferenceFrames().contains(.xArbitraryZVertical) else {
            return "이 기기에서 몸 방향 센서를 쓸 수 없어요."
        }
        manager.deviceMotionUpdateInterval=1.0/30
        manager.startDeviceMotionUpdates(using:.xArbitraryZVertical,to:.main) { [weak self] data,_ in
            guard let self, let r=data?.attitude.rotationMatrix else { return }
            heading=HeadingMath.screenHeadingDegrees(.init(m11:r.m11,m12:r.m12,m13:r.m13,m21:r.m21,m22:r.m22,m23:r.m23,
                                                            m31:r.m31,m32:r.m32,m33:r.m33))
            onHeading(heading)
        }
        return nil
    }
    func stop() { manager.stopDeviceMotionUpdates();heading=nil }
}
