import SwiftUI

/// 지금 소리가 어디로 나가는지 한 줄. AirPods 가 아니면 무엇을 하라고 말한다.
struct OutputBanner: View {
    @EnvironmentObject private var cues: AudioCuePlayer
    var body: some View {
        normal
    }

    private var normal: some View {
        HStack(spacing: 10) {
            Image(systemName: cues.isHeadphones ? "airpods" : "speaker.wave.2")
                .font(.title3)
                .foregroundStyle(cues.isHeadphones ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(cues.isHeadphones ? "소리가 \(cues.outputName)로 나가요" : "지금은 \(cues.outputName)로 나가요")
                    .font(.subheadline.weight(.semibold))
                if !cues.isHeadphones {
                    Text("AirPods를 끼고 연결해 주세요").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// AirPods 가 빠졌을 때 **어느 화면에서든** 맨 위에 뜨는 경고. 앱 전체에 한 번 붙인다.
struct HeadphonesLostBanner: View {
    @EnvironmentObject private var cues: AudioCuePlayer
    var body: some View {
        if cues.headphonesLost {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("AirPods가 빠졌어요 — 안내음을 멈췄어요").font(.headline)
                    Text("무용수에게 알려 주세요. 다시 끼우면 자동으로 다시 나요. 폰 스피커로는 나가지 않아요.")
                        .font(.caption)
                    if cues.isHeadphones {
                        Button("다시 켜기") { cues.resumeAfterLoss() }
                            .buttonStyle(.borderedProminent)
                            .tint(.white)
                            .foregroundStyle(.red)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding()
            .background(.red)
        }
    }
}

// MARK: - 2 소리 신호 맞히기

/// **테스트 2 · 소리 신호 맞히기 (E1 · E2 의 소리판)**
///
/// Watch 진동 대신 AirPods 소리로 같은 다섯 뜻을 내고 맞힌다. 통과 기준은 진동과 같은 90%.
/// "소리"(짧은 음)와 "말"(음성)을 따로 기록한다 — 말은 뜻이 분명한 대신 길고 음악을 더 가린다.
struct SoundSignalView: View {
    @EnvironmentObject private var cues: AudioCuePlayer
    @EnvironmentObject private var store: TrialStore

    private enum Posture: String, CaseIterable, Identifiable {
        case still = "가만히 서서", walking = "걸으면서", dancing = "춤추면서"
        var id: String { rawValue }
    }
    private enum Phase { case setup, learn, quiz, done }

    private static let total = 40
    private let signals = GuideSignal.commands

    @State private var phase: Phase = .setup
    @State private var posture: Posture = .still
    /// 음악을 틀고 하는 판(E3). 조용한 판과 섞이지 않게 조건 이름에 붙인다.
    @State private var withMusic = false
    @State private var presented: GuideSignal?
    @State private var presentedAt = Date()
    @State private var results: [(expected: GuideSignal, answered: GuideSignal)] = []

    private var condition: String {
        "\(cues.recordName) · \(posture.rawValue)" + (withMusic ? " · 음악" : "")
    }

    var body: some View {
        Group {
            switch phase {
            case .setup: setup
            case .learn: learn
            case .quiz: quiz
            case .done: done
            }
        }
        .navigationTitle("2 소리 신호 맞히기")
    }

    private var setup: some View {
        List {
            Section {
                HowToCard(what: "소리만 듣고 신호 뜻을 맞히나", steps: [
                    "AirPods를 끼고, 신호 종류와 자세를 골라요",
                    "신호 다섯 개를 들어 보며 외워요",
                    "눈을 감고, 들린 신호를 눌러요. 40번",
                ])
                OutputBanner()
            }
            Section("신호 종류") {
                Picker("신호 종류", selection: $cues.style) {
                    ForEach(AudioCuePlayer.Style.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(cues.style == .tone ? "짧은 음이에요. 왼쪽은 삐삐 두 번, 오른쪽은 삐 한 번. 한쪽 AirPod가 빠져도 개수로 알 수 있어요." : "“왼쪽”처럼 말로 알려 줘요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("어떻게 하면서") {
                Picker("자세", selection: $posture) {
                    ForEach(Posture.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("처음엔 ‘가만히 서서’부터 해요.").font(.caption).foregroundStyle(.secondary)
            }
            Section("소리 환경") {
                Toggle("음악 틀고 하기", isOn: $withMusic)
                Text("다른 기기(노트북·스피커)로 음악을 틀어요. 결과가 조용한 판과 따로 남아요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                StartButton(title: "신호 외우러 가기") {
                    results = []
                    phase = .learn
                }
            }
        }
    }

    private var learn: some View {
        List {
            Section {
                ForEach(signals) { s in
                    Button { cues.play(s) } label: {
                        HStack {
                            Image(systemName: s.symbol).frame(width: 28)
                            VStack(alignment: .leading) {
                                Text(meaning(s)).font(.headline)
                                Text(cues.style == .tone ? cues.sound(s) : "“\(cues.word(s))”")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("눌러서 들어 봐요 · 방향은 내 몸 기준")
            }
            Section {
                StartButton(title: "다 외웠어요") {
                    phase = .quiz
                    afterPause { present() }
                }
            }
        }
    }

    private var quiz: some View {
        VStack(spacing: 16) {
            ProgressHeader(label: condition, done: results.count, total: Self.total)
            Text("무슨 신호였어요?").font(.title3.weight(.semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(signals) { s in
                    Button { answer(s) } label: {
                        Label(meaning(s), systemImage: s.symbol)
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 64)
                    }
                    .buttonStyle(.bordered)
                }
            }
            HStack {
                Button { if let s = presented { cues.play(s) } } label: {
                    Label("다시 듣기", systemImage: "arrow.counterclockwise")
                }
                Spacer()
                Button("그만하고 결과 보기") { phase = .done }.foregroundStyle(.secondary)
            }
            .font(.subheadline)
            Spacer()
        }
        .padding()
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
        return List {
            Section(condition) {
                Label(acc >= 0.9 ? "통과 (\(Int(acc * 100))%)" : "90%에 못 미쳐요 (\(Int(acc * 100))%)",
                      systemImage: acc >= 0.9 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(acc >= 0.9 ? .green : .orange)
                    .font(.headline)
                ResultRow(name: "맞힌 수", value: "\(hit) / \(n)")
            }
            Section("자주 헷갈린 것") {
                if mixups.isEmpty { Text("없어요") }
                ForEach(Array(mixups), id: \.0) { ResultRow(name: $0.0, value: "\($0.1)번") }
            }
            Section {
                Text("결과는 ‘결과’ 탭에도 남아요.").font(.footnote).foregroundStyle(.secondary)
                Button("처음부터 다시") { phase = .setup }
            }
        }
    }

    private func meaning(_ s: GuideSignal) -> String {
        switch s {
        case .left: return "왼쪽으로"
        case .right: return "오른쪽으로"
        case .back: return "뒤로"
        default: return s.korean
        }
    }

    private func present() {
        let s = signals.randomElement()!
        presented = s
        presentedAt = Date()
        cues.play(s)
    }

    private func answer(_ s: GuideSignal) {
        guard let expected = presented else { return }
        store.add(Trial(experiment: "E1-AirPods",
                        condition: condition,
                        expected: expected.rawValue,
                        answered: s.rawValue,
                        reactionMs: Date().timeIntervalSince(presentedAt) * 1000))
        results.append((expected, s))
        presented = nil
        if results.count < Self.total {
            afterPause { present() }
        } else {
            phase = .done
        }
    }
}

// MARK: - 3 AirPods 빼 보기

/// **테스트 3 · AirPods 빼 보기 (E9 의 일부)**
///
/// 안내음을 반복해 두고 AirPods 를 한쪽, 그다음 양쪽 뺀다. 소리가 멈추는지 **폰 스피커로 새는지** 본다.
/// 스피커로 새면 공연 중 객석으로 안내음이 나가는 사고다(문서 B2.6).
///
/// 이 화면의 재생기는 출력 장치가 바뀌어 엔진이 멈추면 다음 반복에서 **그대로 다시 켠다.**
/// 아무 대책 없는 앱이 어떻게 되는지를 보려는 것이므로 일부러 막지 않는다.
struct AirPodsOutView: View {
    @EnvironmentObject private var cues: AudioCuePlayer
    @EnvironmentObject private var store: TrialStore

    private enum Phase { case setup, one, both, done }
    @State private var phase: Phase = .setup
    @State private var answers: [String: String] = [:]

    var body: some View {
        List {
            switch phase {
            case .setup:
                Section {
                    HowToCard(what: "AirPods가 빠지면 소리가 어디로 가나", steps: [
                        "AirPods 양쪽을 끼고 ‘시작’을 눌러요",
                        "1초쯤마다 신호음이 나요",
                        "화면이 시키는 대로 한쪽, 그다음 양쪽을 빼 보고 들리는 대로 답해요",
                    ])
                    OutputBanner()
                }
                Section {
                    Text("조용한 곳에서 해요. 폰 스피커 소리가 날 수 있어요.")
                        .font(.footnote).foregroundStyle(.secondary)
                    StartButton(title: "시작") {
                        answers = [:]
                        cues.clearLog()
                        // 대책 없는 앱이 어떻게 되는지 보는 화면이라 안전 멈춤을 끈다
                        cues.safetyStop = false
                        cues.style = .tone
                        cues.startRepeating(.back, every: .slight)
                        phase = .one
                    }
                    .disabled(!cues.isHeadphones)
                }
            case .one:
                question(step: "1/2", ask: "AirPods를 한쪽만 빼 보세요.\n소리가 어떻게 됐어요?",
                         options: ["끼운 쪽에서 계속 들려요", "멈췄어요", "폰 스피커에서 나와요"]) { a in
                    record("한쪽", a)
                    phase = .both
                }
            case .both:
                question(step: "2/2", ask: "뺀 쪽을 다시 끼운 뒤, 이번엔 양쪽 다 빼 보세요.\n소리가 어떻게 됐어요?",
                         options: ["멈췄어요", "폰 스피커에서 나와요", "잘 모르겠어요"]) { a in
                    record("양쪽", a)
                    cues.stop()
                    phase = .done
                }
            case .done:
                let leaked = answers.values.contains("폰 스피커에서 나와요")
                Section {
                    Label(leaked ? "소리가 폰 스피커로 샜어요" : "빠지면 소리가 멈췄어요",
                          systemImage: leaked ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(leaked ? .orange : .green)
                        .font(.headline)
                    ForEach(["한쪽", "양쪽"], id: \.self) { k in
                        ResultRow(name: "\(k) 뺐을 때", value: answers[k] ?? "—")
                    }
                    Text(leaked
                         ? "공연 중이면 안내음이 객석으로 나가요. AirPods가 빠지면 앱이 소리를 멈추게 고쳐야 해요."
                         : "빠지면 조용해져요. 대신 무용수는 안내가 끊긴 걸 모를 수 있어요.")
                        .font(.footnote)
                }
                routeLogSection
                Section { Button("처음부터 다시") { phase = .setup } }
            }
        }
        .navigationTitle("3 AirPods 빼 보기")
        .onDisappear {
            cues.stop()
            cues.safetyStop = true
        }
    }

    private func question(step: String, ask: String, options: [String],
                          onAnswer: @escaping (String) -> Void) -> some View {
        Group {
            Section {
                Text(step).font(.caption).foregroundStyle(.secondary)
                Text(ask).font(.title3.weight(.semibold))
                ForEach(options, id: \.self) { o in
                    Button { onAnswer(o) } label: {
                        Text(o).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
            Section("앱이 본 출력 장치") {
                ResultRow(name: "지금", value: cues.outputName, good: cues.isSpeaker ? false : nil)
            }
            routeLogSection
        }
    }

    private var routeLogSection: some View {
        Section("출력 변화 기록") {
            if cues.routeLog.isEmpty { Text("아직 없어요").foregroundStyle(.secondary) }
            ForEach(cues.routeLog.suffix(6), id: \.self) { Text($0).font(.caption.monospacedDigit()) }
        }
    }

    private func record(_ step: String, _ answer: String) {
        answers[step] = answer
        store.add(Trial(experiment: "E9-AirPods",
                        condition: step,
                        expected: "멈춤",
                        answered: answer,
                        reactionMs: 0,
                        note: "출력 \(cues.outputName) · " + cues.routeLog.suffix(3).joined(separator: " / ")))
    }
}

// MARK: - 공용

struct ProgressHeader: View {
    let label: String
    let done: Int
    let total: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(min(done + 1, total))/\(total)").monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: Double(done), total: Double(total)).tint(.yellow)
        }
    }
}

struct StartButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
        .tint(.yellow)
        .foregroundStyle(.black)
    }
}
