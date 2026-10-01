import SwiftUI

/// **테스트 7 · 신호 맞히기 (E1 · E2)**
///
/// 안 C의 신호를 무작위로 울리고 무엇인지 맞힌다. 문서의 통과 기준 초안은 90%다.
/// **가만히 서서 잰 값을 춤추는 중 성능으로 일반화하면 안 된다** — 그래서 자세를 먼저 고르게 하고
/// 자세마다 실험 이름을 따로 남긴다(E1 / E2-걷기 / E2-안무).
///
/// 작동 신호는 명령이 아니라 배경이라 문제에서 뺀다. 게다가 지금은 "오른쪽"과 같은 진동이다.
struct SignalIDView: View {
    @EnvironmentObject private var player: HapticPlayer
    @EnvironmentObject private var store: TrialStore

    private enum Posture: String, CaseIterable {
        case still = "가만히 서서", walking = "걸으면서", dancing = "춤추면서"
        var experiment: String {
            switch self {
            case .still:   return "E1"
            case .walking: return "E2-걷기"
            case .dancing: return "E2-안무"
            }
        }
    }
    private enum Phase { case intro, learn, quiz, done }

    private static let total = 40
    private let signals = GuideSignal.commands

    @State private var phase: Phase = .intro
    @State private var posture: Posture = .still
    @State private var presented: GuideSignal?
    @State private var presentedAt = Date()
    @State private var results: [(expected: GuideSignal, answered: GuideSignal)] = []

    var body: some View {
        Group {
            switch phase {
            case .intro: intro
            case .learn: learn
            case .quiz: quiz
            case .done: done
            }
        }
        .navigationTitle("7 신호 맞히기")
    }

    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("눈 감고 신호 뜻을 맞히나").font(.headline)
                Text("먼저 신호를 외우고, 40번 맞혀요. 어떻게 하면서 할까요?")
                    .font(.footnote)
                ForEach(Posture.allCases, id: \.self) { p in
                    BigButton(title: p.rawValue, symbol: symbol(p), tint: p == .still ? .yellow : .gray) {
                        posture = p
                        results = []
                        phase = .learn
                    }
                }
                Text("처음엔 ‘가만히 서서’부터 해요.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func symbol(_ p: Posture) -> String {
        switch p {
        case .still: return "figure.stand"
        case .walking: return "figure.walk"
        case .dancing: return "figure.dance"
        }
    }

    private var learn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("신호 외우기").font(.headline)
                Text("눌러서 느껴 봐요. 방향은 내 몸 기준이에요.")
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(signals) { s in
                    Button { player.play(s) } label: {
                        HStack {
                            Image(systemName: s.symbol).frame(width: 22)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(meaning(s)).font(.footnote.weight(.semibold))
                                Text(s.feel).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                Text("작동 신호(약한 톡)는 문제에 안 나와요. 지금은 ‘오른쪽’과 같은 진동이에요.")
                    .font(.caption2).foregroundStyle(.secondary)
                BigButton(title: "다 외웠어요", symbol: "arrow.right") {
                    phase = .quiz
                    afterPause { present() }
                }
            }
        }
    }

    private var quiz: some View {
        ScrollView {
            VStack(spacing: 8) {
                ProgressLine(label: posture.rawValue, done: results.count, total: Self.total)
                Text("무슨 신호였어요?").font(.footnote)
                AnswerGrid(options: signals.map(meaning), columns: 2) { answer(signals[$0]) }
                ReplayButton { if let s = presented { player.play(s) } }
                Button("여기서 그만하고 결과 보기") { phase = .done }
                    .font(.caption2).buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }

    private var done: some View {
        let n = results.count
        let hit = results.filter { $0.expected == $0.answered }.count
        let acc = n == 0 ? 0 : Double(hit) / Double(n)
        let mixups = Dictionary(grouping: results.filter { $0.expected != $0.answered },
                                by: { "\(meaning($0.expected)) → \(meaning($0.answered))" })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map { "\($0.0) \($0.1)번" }
        return DoneView(
            headline: acc >= 0.9 ? "통과 (\(Int(acc * 100))%)" : "90%에 못 미쳐요 (\(Int(acc * 100))%)",
            tone: acc >= 0.9 ? .good : .bad,
            lines: ["\(posture.rawValue) · \(n)번 중 \(hit)번 맞힘"]
                + (mixups.isEmpty ? ["헷갈린 신호 없음"] : ["자주 헷갈린 것:"] + mixups)
        ) { phase = .intro }
    }

    /// 버튼에 쓰는 말. "왼쪽"보다 "왼쪽으로"가 무엇을 해야 하는지 더 분명하다.
    private func meaning(_ s: GuideSignal) -> String {
        switch s {
        case .left: return "왼쪽으로"
        case .right: return "오른쪽으로"
        case .back: return "뒤로"
        case .arrive: return "도착"
        case .stop: return "정지"
        case .heartbeat: return "작동 신호"
        }
    }

    private func present() {
        let s = signals.randomElement()!
        presented = s
        presentedAt = Date()
        player.play(s)
    }

    private func answer(_ s: GuideSignal) {
        guard let expected = presented else { return }
        store.add(Trial(experiment: posture.experiment,
                        condition: posture.rawValue,
                        expected: expected.rawValue,
                        answered: s.rawValue,
                        reactionMs: Date().timeIntervalSince(presentedAt) * 1000,
                        note: posture.rawValue))
        results.append((expected, s))
        presented = nil
        if results.count < Self.total {
            afterPause { present() }
        } else {
            phase = .done
        }
    }
}
