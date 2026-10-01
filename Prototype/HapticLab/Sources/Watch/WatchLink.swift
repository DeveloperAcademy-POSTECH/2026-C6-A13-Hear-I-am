import Foundation
import WatchConnectivity

/// iPhone 과의 연결. 문서 §B1.6 — WatchConnectivity 로는 한 번에 한 대만 통신한다.
@MainActor
final class WatchLink: NSObject, ObservableObject {
    @Published private(set) var isReachable = false
    @Published private(set) var received = 0
    @Published private(set) var dropped = 0
    @Published private(set) var lastSignal: GuideSignal?

    private let player: HapticPlayer
    private let watchdog: Watchdog

    init(player: HapticPlayer, watchdog: Watchdog) {
        self.player = player
        self.watchdog = watchdog
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    fileprivate func handle(_ command: GuideCommand) -> GuideAck {
        let start = Date()
        watchdog.noteUpdate()
        received += 1

        // §A5.2 — 늦게 도착한 지시는 틀린 지시다. 유효 시간이 지났으면 버린다.
        let ageMs = Date().timeIntervalSince(command.sentAt) * 1000
        if ageMs > Double(command.validForMs) {
            dropped += 1
            return GuideAck(commandId: command.id, onWatchMs: 0, wasDropped: true, wasPreempted: false)
        }

        var preempted = false
        if command.silence == true {
            // 잘 가고 있다 — 반복을 멈추고 침묵으로 돌아간다
            player.stop()
            lastSignal = nil
            return GuideAck(commandId: command.id, onWatchMs: Date().timeIntervalSince(start) * 1000,
                            wasDropped: false, wasPreempted: false)
        } else if command.isProbe {
            // 지연 측정용 탐침. 신호 의미와 섞이지 않도록 가장 약한 탭 하나만 낸다.
            player.playRaw(HapticPattern(taps: [HapticTap(kind: .click, gapMs: 0)]))
        } else if let deviation = command.deviation {
            player.startRepeating(command.signal, every: deviation)
        } else {
            preempted = !player.play(command.signal)
        }
        lastSignal = command.signal
        return GuideAck(commandId: command.id,
                        onWatchMs: Date().timeIntervalSince(start) * 1000,
                        wasDropped: false,
                        wasPreempted: preempted)
    }

    func resetCounters() {
        received = 0
        dropped = 0
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard let command = GuideCommand(dictionary: message) else {
            replyHandler([:]); return
        }
        Task { @MainActor in
            let ack = self.handle(command)
            replyHandler(ack.dictionary)
        }
    }
}
