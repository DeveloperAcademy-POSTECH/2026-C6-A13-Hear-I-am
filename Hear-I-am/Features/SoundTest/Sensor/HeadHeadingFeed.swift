import CoreMotion
import HearIAmCore

/// AirPods head heading. Positive is a right turn: HapticLab measured yaw −92.5° for a right turn.
/// Only changes are meaningful. Whether one earbud alone reports motion is what this tab checks.
@MainActor final class HeadHeadingFeed: NSObject, CMHeadphoneMotionManagerDelegate {
    private let manager=CMHeadphoneMotionManager()
    private(set) var heading: Double?
    private(set) var lastSample: Double?
    private(set) var connected=false
    var onStatus: ((String)->Void)?

    func start(_ onHeading: @escaping (Double?) -> Void) {
        manager.delegate=self
        guard manager.isDeviceMotionAvailable else { onStatus?("이 기기는 에어팟 고개 추적을 지원하지 않아요.");return }
        if CMHeadphoneMotionManager.authorizationStatus() == .denied { onStatus?("움직임 권한이 꺼져 있어요. 설정에서 켜 주세요.");return }
        manager.startDeviceMotionUpdates(to:.main) { [weak self] data,error in
            guard let self else { return }
            if let error { onStatus?("고개 값 오류: "+error.localizedDescription);return }
            guard let yaw=data?.attitude.yaw else { return }
            heading=HeadingMath.wrapDegrees(-yaw*180 / .pi);lastSample=ProcessInfo.processInfo.systemUptime
            onHeading(heading)
        }
        onStatus?("에어팟을 기다리는 중")
    }
    func stop() { manager.stopDeviceMotionUpdates();heading=nil;lastSample=nil }

    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in connected=true;onStatus?("에어팟 연결됨") }
    }
    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in connected=false;heading=nil;onStatus?("에어팟 연결 끊김") }
    }
}
