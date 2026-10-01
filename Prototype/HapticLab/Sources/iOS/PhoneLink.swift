import Foundation
import WatchConnectivity

/// 운영자 iPhone → 무용수 Watch.
/// 문서 §B1.6 — WatchConnectivity 로는 한 번에 한 대만 통신한다. 여러 명은 다른 경로가 필요하다.
@MainActor
final class PhoneLink: NSObject, ObservableObject {
    @Published private(set) var isPaired = false
    @Published private(set) var isReachable = false
    @Published private(set) var isInstalled = false
    @Published private(set) var lastError: String?

    /// 왕복 시간(ms). iPhone 시계만으로 재므로 두 기기의 시계 차이에 영향받지 않는다.
    @Published private(set) var roundTripsMs: [Double] = []
    /// Watch 안에서 수신부터 재생 호출까지 걸린 시간(ms)
    @Published private(set) var onWatchMs: [Double] = []
    @Published private(set) var droppedCount = 0
    @Published private(set) var failedCount = 0

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ command: GuideCommand) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            lastError = "Watch 에 닿지 않는다"
            failedCount += 1
            return
        }
        let sentAt = Date()
        session.sendMessage(command.dictionary, replyHandler: { [weak self] reply in
            let rtt = Date().timeIntervalSince(sentAt) * 1000
            Task { @MainActor in
                guard let self else { return }
                self.roundTripsMs.append(rtt)
                if let ack = GuideAck(dictionary: reply) {
                    self.onWatchMs.append(ack.onWatchMs)
                    if ack.wasDropped { self.droppedCount += 1 }
                }
            }
        }, errorHandler: { [weak self] error in
            let message = error.localizedDescription
            Task { @MainActor in
                self?.lastError = message
                self?.failedCount += 1
            }
        })
    }

    func reset() {
        roundTripsMs.removeAll()
        onWatchMs.removeAll()
        droppedCount = 0
        failedCount = 0
        lastError = nil
    }

    /// 문서 §C — 평균만 쓰지 않는다. 95백분위와 최대값을 같이 남긴다.
    var summary: (n: Int, median: Double, p95: Double, max: Double)? {
        guard !roundTripsMs.isEmpty else { return nil }
        return (roundTripsMs.count,
                TrialStore.percentile(roundTripsMs, 0.5) ?? 0,
                TrialStore.percentile(roundTripsMs, 0.95) ?? 0,
                roundTripsMs.max() ?? 0)
    }
}

extension PhoneLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        let reachable = session.isReachable
        Task { @MainActor in
            self.isPaired = paired
            self.isInstalled = installed
            self.isReachable = reachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // 다른 Watch 로 전환되면 세션이 해제된다. 다시 활성화해야 새 Watch 와 연결된다.
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    /// 시계 앱 설치·페어링이 바뀌면 안내 문구도 바뀌어야 한다.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        Task { @MainActor in
            self.isPaired = paired
            self.isInstalled = installed
        }
    }
}
