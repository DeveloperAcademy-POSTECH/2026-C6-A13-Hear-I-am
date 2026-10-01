import SwiftUI

@main
struct HapticLabWatchApp: App {
    @StateObject private var player = HapticPlayer()
    @StateObject private var store = TrialStore()
    @StateObject private var session = WorkoutKeeper()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(player)
                .environmentObject(store)
                .environmentObject(session)
        }
    }
}

/// 첫 화면. 번호는 테스트 안내 페이지의 번호와 같다(1~4는 시계 없이 폰에서 한다).
struct RootView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("혼자 하는 테스트") {
                    NavigationLink { IntervalLabView() } label: {
                        MenuRow(number: "5", title: "진동 간격", detail: "톡톡을 얼마나 빨리 칠 수 있나")
                    }
                    NavigationLink { IntensityLabView() } label: {
                        MenuRow(number: "6", title: "진동 세기", detail: "세고 약한 걸 구분하나")
                    }
                    NavigationLink { SignalIDView() } label: {
                        MenuRow(number: "7", title: "신호 맞히기", detail: "눈 감고 뜻을 맞히나")
                    }
                    NavigationLink { KeepAliveView() } label: {
                        MenuRow(number: "8", title: "계속 울리나", detail: "화면이 꺼져도 오나")
                    }
                }
                Section("폰과 같이") {
                    NavigationLink { ReceiverView() } label: {
                        MenuRow(number: "9·10", title: "폰 신호 받기", detail: "폰에서 보내는 신호를 받아요")
                    }
                }
                Section {
                    NavigationLink { ResultsView() } label: {
                        MenuRow(number: "✓", title: "지난 결과", detail: "앱을 꺼도 남아 있어요")
                    }
                }
            }
            .navigationTitle("HapticLab")
        }
    }
}

private struct MenuRow: View {
    let number: String
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(.footnote, design: .rounded).weight(.bold))
                .frame(minWidth: 26, minHeight: 26)
                .background(Circle().fill(.yellow.opacity(0.9)))
                .foregroundStyle(.black)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 공용 화면 조각
// 휠 피커는 스크롤·크라운과 입력을 다투므로 쓰지 않는다. 전부 크게 누르는 버튼이다.
// 테스트는 모두 "설명 → 진행 → 결과" 세 단계로 같은 모양을 쓴다.

/// 테스트 첫 화면. 무엇을 하는지 두세 줄, 그리고 시작 버튼.
struct IntroView<Extra: View>: View {
    let what: String
    let how: [String]
    var startTitle = "시작"
    @ViewBuilder var extra: Extra
    let onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(what).font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(how.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(i + 1)").font(.caption2.weight(.bold)).foregroundStyle(.yellow)
                            Text(how[i]).font(.footnote)
                        }
                    }
                }
                extra
                BigButton(title: startTitle, symbol: "play.fill", action: onStart)
            }
        }
    }
}

extension IntroView where Extra == EmptyView {
    init(what: String, how: [String], startTitle: String = "시작", onStart: @escaping () -> Void) {
        self.init(what: what, how: how, startTitle: startTitle, extra: { EmptyView() }, onStart: onStart)
    }
}

/// 진행 중 맨 위 한 줄: 무엇을 하는 중인지 + 몇 번째인지.
struct ProgressLine: View {
    let label: String
    let done: Int
    let total: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text("\(min(done + 1, total))/\(total)")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .tint(.yellow)
        }
    }
}

/// 결과 화면. 맨 위 한 줄이 판정이고, 아래는 근거 숫자.
struct DoneView: View {
    enum Tone { case good, bad, neutral }
    let headline: String
    var tone: Tone = .neutral
    let lines: [String]
    let onAgain: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Label(headline, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(color)
                ForEach(lines, id: \.self) { Text($0).font(.footnote) }
                Text("결과는 저장됐어요. 첫 화면 ‘지난 결과’에서 다시 볼 수 있어요.")
                    .font(.caption2).foregroundStyle(.secondary)
                Button("처음부터 다시", action: onAgain).buttonStyle(.bordered)
            }
        }
    }

    private var symbol: String {
        switch tone {
        case .good: return "checkmark.circle.fill"
        case .bad: return "exclamationmark.triangle.fill"
        case .neutral: return "info.circle.fill"
        }
    }
    private var color: Color {
        switch tone {
        case .good: return .green
        case .bad: return .orange
        case .neutral: return .primary
        }
    }
}

/// 답 버튼 격자. 누르는 즉시 기록한다(따로 "기록" 버튼을 두지 않는다).
struct AnswerGrid: View {
    let options: [String]
    var columns = 2
    let onAnswer: (Int) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
            ForEach(options.indices, id: \.self) { i in
                Button { onAnswer(i) } label: {
                    Text(options[i])
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// 화면 가득 찬 주 버튼.
struct BigButton: View {
    let title: String
    let symbol: String
    var tint: Color = .yellow
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .foregroundStyle(tint == .yellow ? .black : .white)
    }
}

/// "다시 듣기" 작은 버튼.
struct ReplayButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("다시 듣기", systemImage: "arrow.counterclockwise")
                .font(.caption)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

/// 답한 뒤 다음 문제를 잠깐 쉬었다 내보낸다. 바로 울리면 방금 답한 손가락 감각과 섞인다.
@MainActor
func afterPause(_ action: @escaping @MainActor () -> Void) {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 700_000_000)
        action()
    }
}
