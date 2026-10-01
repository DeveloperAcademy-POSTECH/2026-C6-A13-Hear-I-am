import Foundation
import WatchKit

/// 탭 시퀀스를 실제로 울리는 엔진.
///
/// 지키는 규칙 두 가지 — 둘 다 문서에서 왔다.
/// 1. §B1.3 : `play(_:)` 를 빠르게 연속 호출하면 시스템이 현재 것을 끊고 최소 100ms 를 강제한다.
///    그러므로 탭 사이 간격의 하한을 우리가 먼저 지킨다.
/// 2. §A5.2 : 한 번에 하나만 내보낸다. 순위가 낮은 신호는 **버린다** — 큐에 쌓아 두지 않는다.
@MainActor
final class HapticPlayer: ObservableObject {
    static let minimumGapMs = 100

    @Published private(set) var nowPlaying: GuideSignal?
    @Published private(set) var lastPlayedAt: Date?
    /// 우선순위에 밀려 버린 지시의 수. 실험에서 그대로 기록한다.
    @Published private(set) var preemptedCount = 0

    private var task: Task<Void, Never>?
    private var playingPriority = Int.max

    /// 신호 하나를 한 번 울린다. 이미 더 높은 순위가 울리는 중이면 **버린다.**
    /// - Returns: 실제로 재생했으면 true
    @discardableResult
    func play(_ signal: GuideSignal) -> Bool {
        if let _ = nowPlaying, signal.priority > playingPriority {
            preemptedCount += 1
            return false
        }
        task?.cancel()
        playingPriority = signal.priority
        nowPlaying = signal
        let pattern = SignalBook.pattern(for: signal)
        task = Task { [weak self] in
            await self?.run(pattern)
            guard !Task.isCancelled else { return }
            self?.nowPlaying = nil
            self?.playingPriority = .max
            self?.lastPlayedAt = Date()
        }
        return true
    }

    /// 통로에서 벗어난 상태를 **반복 간격**으로 표현한다(§A4 안 C).
    /// 방향이 맞으면 이 메서드를 부르지 않는다 — 침묵이 정상이다.
    func startRepeating(_ signal: GuideSignal, every deviation: Deviation) {
        task?.cancel()
        playingPriority = signal.priority
        nowPlaying = signal
        let pattern = SignalBook.pattern(for: signal)
        let period = UInt64(deviation.repeatMs) * 1_000_000
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.run(pattern)
                try? await Task.sleep(nanoseconds: period)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        nowPlaying = nil
        playingPriority = .max
    }

    /// 임의의 패턴을 그대로 재생한다(E6-1 에서 간격을 바꿔 가며 쓴다).
    func playRaw(_ pattern: HapticPattern) {
        task?.cancel()
        playingPriority = 0
        nowPlaying = nil
        task = Task { [weak self] in await self?.run(pattern) }
    }

    private func run(_ pattern: HapticPattern) async {
        for tap in pattern.taps {
            if Task.isCancelled { return }
            let gap = max(tap.gapMs, tap.gapMs == 0 ? 0 : Self.minimumGapMs)
            if gap > 0 {
                try? await Task.sleep(nanoseconds: UInt64(gap) * 1_000_000)
            }
            if Task.isCancelled { return }
            WKInterfaceDevice.current().play(tap.kind.wkType)
        }
    }

    func resetCounters() { preemptedCount = 0 }
}

extension HapticTap.Kind {
    var wkType: WKHapticType {
        switch self {
        case .click:         return .click
        case .success:       return .success
        case .failure:       return .failure
        case .start:         return .start
        case .stop:          return .stop
        case .retry:         return .retry
        case .notification:  return .notification
        case .directionUp:   return .directionUp
        case .directionDown: return .directionDown
        }
    }
}

/// 문서 §A5.3 — 침묵이 "정상"과 "고장"을 동시에 뜻하지 않게 한다.
/// 정상일 때도 주기적으로 약한 탭을 내고, 갱신이 끊기면 Watch 가 **스스로** 중단 신호를 낸다.
@MainActor
final class Watchdog: ObservableObject {
    @Published private(set) var isAlive = false
    @Published private(set) var lastUpdate: Date?

    /// 이 시간 동안 갱신이 없으면 죽은 것으로 본다.
    var timeoutSec: TimeInterval = 3.0

    private var timer: Task<Void, Never>?
    private unowned let player: HapticPlayer

    init(player: HapticPlayer) { self.player = player }

    func noteUpdate() { lastUpdate = Date() }

    func start() {
        isAlive = true
        lastUpdate = Date()
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(SignalBook.heartbeatPeriodSec * 1_000_000_000))
                guard let self, self.isAlive else { return }
                if let last = self.lastUpdate, Date().timeIntervalSince(last) > self.timeoutSec {
                    // iPhone 이 보내는 정지 신호는 도착하지 않는다. Watch 가 직접 알린다.
                    self.player.play(.stop)
                } else {
                    self.player.play(.heartbeat)
                }
            }
        }
    }

    func stop() {
        isAlive = false
        timer?.cancel()
        timer = nil
    }
}
