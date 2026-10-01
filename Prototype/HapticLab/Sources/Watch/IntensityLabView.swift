import SwiftUI

/// **테스트 6 · 진동 세기 (E6-2)**
///
/// `SensoryFeedback.impact(weight:intensity:)` 는 watchOS 10부터 있고 세기를 0~1로 받는다.
/// 그런데 문서가 이렇게 경고한다 —
/// *"Not all platforms will play different feedback for different weights and intensities of impact."*
/// 즉 **값을 받는다는 것과 실제로 다르게 느껴진다는 것은 다른 문제다.** 그것을 여기서 가른다.
///
/// 세기 30번 → 무게 30번. 각각 먼저 단계별로 들어 본 뒤 무작위로 묻는다.
/// 결과에 따라 설계가 바뀐다. 세기를 쓸 수 있으면 안 B를 세기로 표현할 수 있고,
/// 안 C의 이탈 정도를 간격과 세기 두 축으로 줄 수 있다.
struct IntensityLabView: View {
    @EnvironmentObject private var store: TrialStore

    private enum Mode: String, CaseIterable {
        case intensity = "세기", weight = "무게"
        var names: [String] {
            switch self {
            case .intensity: return ["아주 약함", "약함", "보통", "셈", "아주 셈"]
            case .weight:    return ["가볍게", "보통", "무겁게"]
            }
        }
        var experiment: String { "E6-2-\(rawValue)" }
    }
    private enum Phase { case intro, learn(Mode), quiz(Mode), done }

    private static let levels: [Double] = [0.2, 0.4, 0.6, 0.8, 1.0]
    private static let weights: [SensoryFeedback.Weight] = [.light, .medium, .heavy]
    private static let perMode = 30

    @State private var phase: Phase = .intro
    @State private var trigger = 0
    @State private var current: SensoryFeedback = .impact(weight: .medium, intensity: 1.0)
    @State private var presented: Int?
    @State private var presentedAt = Date()
    @State private var count = 0
    /// 이번 회차 답만 모은다. 저장소에는 지난 회차도 섞여 있다.
    @State private var hits: [Mode: [Bool]] = [:]

    var body: some View {
        Group {
            switch phase {
            case .intro: intro
            case .learn(let m): learn(m)
            case .quiz(let m): quiz(m)
            case .done: done
            }
        }
        .navigationTitle("6 진동 세기")
        .sensoryFeedback(trigger: trigger) { current }
    }

    private var intro: some View {
        IntroView(
            what: "세고 약한 진동을 손목이 구분하나",
            how: ["단계별 진동을 먼저 들어 봐요",
                  "무작위로 하나 울려요. 몇 단계였는지 골라요",
                  "세기 30번, 무게 30번이에요"]
        ) {
            hits = [:]
            phase = .learn(.intensity)
        }
    }

    private func learn(_ m: Mode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(m.rawValue) — 먼저 들어 보기").font(.headline)
                Text("눌러서 느껴 봐요").font(.caption2).foregroundStyle(.secondary)
                AnswerGrid(options: m.names, columns: m == .intensity ? 2 : 3) { play(m, $0) }
                BigButton(title: "다 들어봤어요", symbol: "arrow.right") {
                    count = 0
                    phase = .quiz(m)
                    afterPause { present(m) }
                }
            }
        }
    }

    private func quiz(_ m: Mode) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                ProgressLine(label: m.rawValue, done: count, total: Self.perMode)
                Text("방금 건 어느 단계?").font(.footnote)
                AnswerGrid(options: m.names, columns: m == .intensity ? 2 : 3) { answer(m, $0) }
                ReplayButton { if let i = presented { play(m, i) } }
            }
        }
    }

    private var done: some View {
        let parts = Mode.allCases.compactMap { m -> (Mode, Double)? in
            guard let h = hits[m], !h.isEmpty else { return nil }
            return (m, Double(h.filter { $0 }.count) / Double(h.count))
        }
        let usable = parts.filter { $0.1 > chance($0.0) + 0.05 }.map { $0.0.rawValue }
        let lines = parts.map { m, acc in
            "\(m.rawValue): \(Int(acc * 100))% 맞힘 (찍으면 \(Int(chance(m) * 100))%)"
        }
        return DoneView(
            headline: usable.isEmpty ? "세기 차이를 못 느껴요" : "\(usable.joined(separator: "·"))는 구분돼요",
            tone: usable.isEmpty ? .bad : .good,
            lines: lines + [usable.isEmpty
                            ? "신호는 세기 말고 간격으로만 만들어요."
                            : "세기로도 신호를 만들 수 있어요."]
        ) { phase = .intro }
    }

    private func chance(_ m: Mode) -> Double { 1.0 / Double(m.names.count) }

    private func play(_ m: Mode, _ i: Int) {
        current = m == .intensity
            ? .impact(weight: .medium, intensity: Self.levels[i])
            : .impact(weight: Self.weights[i], intensity: 1.0)
        trigger &+= 1
    }

    private func present(_ m: Mode) {
        let i = Int.random(in: 0..<m.names.count)
        presented = i
        presentedAt = Date()
        play(m, i)
    }

    private func answer(_ m: Mode, _ a: Int) {
        guard let i = presented else { return }
        store.add(Trial(experiment: m.experiment,
                        condition: m.rawValue,
                        expected: m.names[i],
                        answered: m.names[a],
                        reactionMs: Date().timeIntervalSince(presentedAt) * 1000))
        hits[m, default: []].append(i == a)
        presented = nil
        count += 1
        if count < Self.perMode {
            afterPause { present(m) }
        } else if m == .intensity {
            phase = .learn(.weight)
        } else {
            phase = .done
        }
    }
}
