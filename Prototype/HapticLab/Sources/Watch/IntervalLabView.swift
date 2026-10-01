import SwiftUI

/// **테스트 5 · 진동 간격 (E6-1)**
///
/// 같은 진동을 정해진 간격으로 5번 치고, **5번이 따로 느껴졌는지**만 묻는다.
/// 문서가 말하는 100ms 하한이 실기기에서 어떻게 나타나는지 보는 것이 목적이다.
///
/// 순서는 앱이 정한다 — 사람이 간격·종류를 직접 돌리게 했더니 조작이 어려웠다.
/// 1) 진동 9종을 하나씩 들려주고 또렷한 것을 고른다 (click 은 비교용으로 늘 넣는다)
/// 2) 고른 종류마다 간격을 500 → 80ms 로 내리며 3번씩 묻는다
struct IntervalLabView: View {
    @EnvironmentObject private var player: HapticPlayer
    @EnvironmentObject private var store: TrialStore

    private enum Phase { case intro, pick, run, done }
    private struct Cond: Hashable { let kind: HapticTap.Kind; let gap: Int }

    private static let gaps = [500, 300, 200, 150, 100, 80]
    private static let repeats = 3
    private static let taps = 5

    @State private var phase: Phase = .intro
    @State private var pickIndex = 0
    @State private var clear: [HapticTap.Kind] = []
    @State private var plan: [Cond] = []
    @State private var index = 0
    @State private var answers: [Cond: [Bool]] = [:]
    @State private var kindsTested: [HapticTap.Kind] = []

    var body: some View {
        Group {
            switch phase {
            case .intro: intro
            case .pick: pick
            case .run: run
            case .done: done
            }
        }
        .navigationTitle("5 진동 간격")
    }

    // MARK: 설명

    private var intro: some View {
        IntroView(
            what: "톡-톡 사이를 얼마나 좁혀도 따로 느껴지나",
            how: ["진동 9가지를 하나씩 들려줘요. 또렷한지 골라요",
                  "고른 진동을 5번씩 쳐요. 점점 빨라져요",
                  "5번이 다 따로 느껴졌는지만 답해요"]
        ) {
            pickIndex = 0
            clear = []
            phase = .pick
            playSample()
        }
    }

    // MARK: 1단계 · 진동 고르기

    private var kinds: [HapticTap.Kind] { HapticTap.Kind.allCases }

    private var pick: some View {
        ScrollView {
            VStack(spacing: 8) {
                ProgressLine(label: "진동 고르기", done: pickIndex, total: kinds.count)
                Text(kinds[pickIndex].rawValue)
                    .font(.title3.weight(.semibold))
                Text("움직이면서도 느껴질 만큼 또렷해요?")
                    .font(.footnote).multilineTextAlignment(.center)
                BigButton(title: "또렷해요", symbol: "hand.thumbsup.fill", tint: .green) { choose(true) }
                BigButton(title: "약해요", symbol: "hand.thumbsdown", tint: .gray) { choose(false) }
                ReplayButton { playSample() }
            }
        }
    }

    private func playSample() {
        player.playRaw(.repeated(kinds[pickIndex], count: 3, gapMs: 500))
    }

    private func choose(_ isClear: Bool) {
        if isClear { clear.append(kinds[pickIndex]) }
        if pickIndex + 1 < kinds.count {
            pickIndex += 1
            afterPause { playSample() }
        } else {
            buildPlan()
        }
    }

    /// click(비교용) + 또렷하다고 고른 것 중 앞의 둘
    private func buildPlan() {
        let chosen = [HapticTap.Kind.click] + clear.filter { $0 != .click }.prefix(2)
        kindsTested = chosen
        plan = chosen.flatMap { kind in
            Self.gaps.flatMap { gap in Array(repeating: Cond(kind: kind, gap: gap), count: Self.repeats) }
        }
        index = 0
        answers = [:]
        phase = .run
        afterPause { playCurrent() }
    }

    // MARK: 2단계 · 간격 재기

    private var run: some View {
        let c = plan[index]
        return ScrollView {
            VStack(spacing: 8) {
                ProgressLine(label: "\(c.kind.rawValue) · \(c.gap)ms", done: index, total: plan.count)
                Text("\(Self.taps)번 울려요.\n다 따로 느껴졌어요?")
                    .font(.footnote).multilineTextAlignment(.center)
                BigButton(title: "\(Self.taps)번 다 셌어요", symbol: "checkmark", tint: .green) { answer(true) }
                BigButton(title: "뭉개졌어요", symbol: "xmark", tint: .orange) { answer(false) }
                ReplayButton { playCurrent() }
                Button("여기서 그만하고 결과 보기") { phase = .done }
                    .font(.caption2).buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }

    private func playCurrent() {
        let c = plan[index]
        player.playRaw(.repeated(c.kind, count: Self.taps, gapMs: c.gap))
    }

    private func answer(_ counted: Bool) {
        let c = plan[index]
        answers[c, default: []].append(counted)
        store.add(Trial(experiment: "E6-1",
                        condition: "\(c.kind.rawValue) gap\(c.gap)ms x\(Self.taps)",
                        expected: "다 셈",
                        answered: counted ? "다 셈" : "뭉개짐",
                        reactionMs: 0))
        if index + 1 < plan.count {
            index += 1
            afterPause { playCurrent() }
        } else {
            phase = .done
        }
    }

    // MARK: 결과

    /// 위에서부터 내려오며, 3번 모두 "다 셈"이었던 가장 짧은 간격. 한 번이라도 뭉개지면 거기서 멈춘다.
    private func floor(for kind: HapticTap.Kind) -> Int? {
        var best: Int?
        for gap in Self.gaps {
            guard let a = answers[Cond(kind: kind, gap: gap)], a.count == Self.repeats, a.allSatisfy({ $0 })
            else { break }
            best = gap
        }
        return best
    }

    private var done: some View {
        let lines = kindsTested.map { kind -> String in
            if let f = floor(for: kind) { return "\(kind.rawValue): \(f)ms까지 또렷" }
            return "\(kind.rawValue): 500ms에서도 뭉개짐"
        }
        let signalGap = SignalBook.tapGapMs
        let clickFloor = floor(for: .click)
        let (headline, tone): (String, DoneView.Tone) = {
            guard let f = clickFloor else { return ("click은 신호로 쓰기 어려워요", .bad) }
            if f <= 100 { return ("지금 신호 간격(\(signalGap)ms) 괜찮아요", .good) }
            if f == 150 { return ("\(signalGap)ms는 경계예요", .neutral) }
            return ("지금 신호 간격(\(signalGap)ms)은 너무 빨라요", .bad)
        }()
        return DoneView(headline: headline, tone: tone,
                        lines: lines + ["왼쪽 신호 ‘톡톡’은 지금 \(signalGap)ms 간격이에요."]) {
            phase = .intro
        }
    }
}
