import SwiftUI
import WatchKit

/// **테스트 8 · 계속 울리나 (E5)**
///
/// 5초마다 톡을 보내고, 손목을 내려 화면이 꺼진 뒤에도 계속 오는지 본다.
/// 사람 느낌만 묻지 않고 **보냈어야 할 수와 실제로 보낸 수**를 같이 남긴다 —
/// 앱이 멈췄다면 실제로 보낸 수가 모자란다.
///
/// 1차는 그냥, 2차는 워크아웃 세션을 켜고. `play()` 문서는 심박 수집 중 햅틱을 치지 말라 하고
/// 워크아웃 문서는 워크아웃 중 햅틱을 전제한다 — 어느 쪽이 맞는지가 공연 길이의 상한을 가른다.
struct KeepAliveView: View {
    @EnvironmentObject private var player: HapticPlayer
    @EnvironmentObject private var store: TrialStore
    @EnvironmentObject private var keeper: WorkoutKeeper

    private enum Mode: String { case plain = "그냥", workout = "워크아웃 켜고" }
    private enum Phase { case intro, run(Mode), done }

    private static let periodSec = 5
    private static let targetSec = 600

    @State private var phase: Phase = .intro
    @State private var startedAt = Date()
    @State private var beats = 0
    @State private var beatTask: Task<Void, Never>?
    @State private var lines: [String] = []

    var body: some View {
        Group {
            switch phase {
            case .intro: intro
            case .run(let m): run(m)
            case .done: done
            }
        }
        .navigationTitle("8 계속 울리나")
    }

    private var intro: some View {
        IntroView(
            what: "화면이 꺼져도 진동이 계속 오나",
            how: ["시작하면 5초마다 톡이 와요",
                  "손목을 내리고 10분 기다려요",
                  "멈추면 손목을 들고 ‘끊겼어요’를 눌러요",
                  "한 번은 그냥, 한 번은 워크아웃을 켜고 해요"]
        ) {
            lines = []
            begin(.plain)
        }
    }

    private func run(_ m: Mode) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(startedAt))
            let expected = elapsed / Self.periodSec + 1
            ScrollView {
                VStack(spacing: 6) {
                    Text(m == .plain ? "1차 · 그냥" : "2차 · 워크아웃 켜고")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(String(format: "%d:%02d", elapsed / 60, elapsed % 60))
                        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    Text("보낸 톡 \(beats) / 보냈어야 할 톡 \(expected)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(beats + 1 < expected ? .orange : .secondary)
                    if elapsed >= Self.targetSec {
                        BigButton(title: "10분 동안 계속 왔어요", symbol: "checkmark", tint: .green) {
                            finish(m, report: "끝까지 옴", elapsed: elapsed, expected: expected)
                        }
                    } else {
                        Text("손목을 내리고 기다려요").font(.footnote)
                    }
                    BigButton(title: "끊겼어요", symbol: "xmark", tint: .orange) {
                        finish(m, report: "끊김", elapsed: elapsed, expected: expected)
                    }
                    if let err = keeper.lastError, m == .workout {
                        Text(err).font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var done: some View {
        DoneView(headline: "두 번 다 끝났어요", tone: .neutral, lines: lines) { phase = .intro }
    }

    private func begin(_ m: Mode) {
        beats = 0
        startedAt = Date()
        phase = .run(m)
        if m == .workout {
            Task {
                await keeper.requestAuthorization()
                keeper.start()
                startBeating()
            }
        } else {
            startBeating()
        }
    }

    private func startBeating() {
        beatTask?.cancel()
        beatTask = Task {
            while !Task.isCancelled {
                player.play(.heartbeat)
                beats += 1
                try? await Task.sleep(nanoseconds: UInt64(Self.periodSec) * 1_000_000_000)
            }
        }
    }

    private func finish(_ m: Mode, report: String, elapsed: Int, expected: Int) {
        beatTask?.cancel()
        beatTask = nil
        if m == .workout { keeper.stop() }
        let minutes = String(format: "%d:%02d", elapsed / 60, elapsed % 60)
        store.add(Trial(experiment: "E5",
                        condition: m.rawValue,
                        expected: "\(expected)",
                        answered: "\(beats)",
                        reactionMs: Double(elapsed) * 1000,
                        note: "\(report) \(minutes)"))
        lines.append("\(m.rawValue): \(report) (\(minutes)) · 톡 \(beats)/\(expected)")
        if m == .plain {
            begin(.workout)
        } else {
            lines.append("워크아웃 기록이 건강 앱에 하나 남았을 수 있어요.")
            phase = .done
        }
    }
}
