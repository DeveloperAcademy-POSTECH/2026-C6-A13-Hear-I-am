import SwiftUI
import AVFoundation

/// **소리 따라 걷기 (등대 방식 · E7 확장)**
///
/// 목표 방향(정면 · 오른쪽 대각선 · 왼쪽 대각선)에 소리를 고정해 두고, 눈을 감은 사람이
/// 소리 나는 쪽으로 몸을 돌려 걸어간다. “앞뒤좌우를 따지지 않고 소리 나는 쪽으로 간다”는
/// 사용자의 제안(2026-09-29)을 카메라 없이 재 보려는 것이다.
///
/// 카메라가 없어 **위치는 모른다.** 재는 것은 **얼굴이 목표 방향을 얼마나 잘 향하는가**다.
/// AirPods 머리 방향을 0.1초마다 적어 두고, 목표와의 차이(오차)를 계산한다.
/// 고개 추적의 부호가 틀렸다면 소리 쪽으로 돌수록 소리가 도망가므로, 이 테스트가 곧 부호 확인도 된다.
struct BeaconWalkView: View {
    @EnvironmentObject private var store: TrialStore
    @StateObject private var engine = SpatialEngine()

    private enum Target: String, CaseIterable, Identifiable {
        case straight = "정면", right = "오른쪽 대각선", left = "왼쪽 대각선", random = "무작위"
        var id: String { rawValue }
    }

    /// 무작위 목표에 쓰는 여덟 방향(앞 = 0°, 시계 방향). 뒤쪽도 들어간다 — 시작 자리에서 방향 잡기(①)를 보려는 것.
    private static let directions: [(name: String, bearing: Double)] = [
        ("정면", 0), ("오른쪽 대각선 앞", 45), ("오른쪽", 90), ("오른쪽 대각선 뒤", 135),
        ("뒤", 180), ("왼쪽 대각선 뒤", 225), ("왼쪽", 270), ("왼쪽 대각선 앞", 315),
    ]

    private func fixed(_ t: Target) -> (name: String, bearing: Double) {
        switch t {
        case .straight: return ("정면", 0)
        case .right: return ("오른쪽 대각선 앞", 45)
        case .left: return ("왼쪽 대각선 앞", 315)
        case .random: return Self.directions.randomElement()!
        }
    }

    private static let walkSeconds = 15.0
    private static let pingEvery: UInt64 = 700_000_000

    @State private var target: Target = .straight
    /// 이번 판의 실제 목표. 무작위면 시작할 때 정한다.
    @State private var goal: (name: String, bearing: Double) = ("정면", 0)
    @State private var task: Task<Void, Never>?
    @State private var samples: [(t: Double, error: Double)] = []
    @State private var result: [String] = []
    @State private var speech = AVSpeechSynthesizer()

    var body: some View {
        List {
            if task != nil, let last = samples.last {
                // 도우미용: 소리는 걷는 사람만 듣는다. 도우미는 이 화면으로 방향을 본다.
                Section {
                    VStack(spacing: 6) {
                        Text("목표: \(goal.name)").font(.headline)
                        Image(systemName: abs(last.error) <= 15 ? "checkmark.circle.fill"
                              : (last.error > 0 ? "arrow.uturn.left.circle.fill" : "arrow.uturn.right.circle.fill"))
                            .font(.system(size: 64))
                        Text(liveWords(last.error)).font(.title2.weight(.bold))
                        Text(String(format: "%+.0f°", last.error)).font(.title3.monospacedDigit())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(abs(last.error) <= 15 ? .green : (abs(last.error) <= 45 ? .orange : .red))
                    .listRowBackground(Color(.secondarySystemBackground))
                } header: {
                    Text("도우미 화면 · 걷는 사람의 얼굴 방향")
                }
            }
            Section {
                HowToCard(what: "소리 나는 쪽으로 몸을 돌려 걸어가나", steps: [
                    "두 사람이 해요. 걷는 사람은 폰에 연결된 AirPods를 끼고, 폰은 주머니에 넣어도 돼요",
                    "‘소리 켜기’ → 걷는 사람이 출발 방향을 보고 서요",
                    "목표를 고르고 ‘시작’. 걷는 사람은 눈을 감아요",
                    "‘무작위’면 도우미 화면에 목표 방향이 떠요. 도우미는 폰을 들고 조용히 그쪽 3m쯤에 가서 서요",
                    "소리는 걷는 사람만 들어요. 도우미는 화면 맨 위의 큰 표시로 걷는 사람이 목표 쪽을 보는지 봐요(초록 = 맞음)",
                    "‘쏴’ 소리가 계속 나요. 소리 나는 쪽으로 몸 전체를 돌려 천천히 걸어가요",
                    "15초 뒤 “멈추세요”라고 해요. 결과가 아래에 나와요",
                ])
            }
            Section("준비") {
                Button(engine.isRunning ? "소리 끄기" : "소리 켜기") {
                    engine.isRunning ? engine.stop() : engine.start()
                }
                ResultRow(name: "머리 방향 읽기", value: engine.headphonesConnected ? "됨" : "아직",
                          good: engine.headphonesConnected)
                Picker("목표", selection: $target) {
                    ForEach(Target.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("목표 쪽에 소리가 고정돼요. 고개를 돌려도 소리는 제자리에 있어요. ‘무작위’는 뒤쪽을 포함한 여덟 방향 중 하나예요.")
                    .font(.caption).foregroundStyle(.secondary)
                if task != nil || !result.isEmpty {
                    ResultRow(name: "이번 목표 (도우미만 보기)", value: goal.name)
                }
            }
            Section {
                if task == nil {
                    StartButton(title: "시작") { start() }
                        .disabled(!engine.isRunning || !engine.headphonesConnected)
                } else {
                    Button("멈추기", role: .destructive) { finish() }
                }
            }
            if !result.isEmpty {
                Section("결과 · 목표 \(goal.name)") {
                    ForEach(result, id: \.self) { Text($0) }
                }
                Section {
                    Text("차이가 ±15° 안이면 목표를 향해 걷고 있다고 봐요. 소리 쪽으로 돌수록 소리가 도망가는 느낌이었다면 알려 주세요 — 고개 추적이 거꾸로라는 뜻이에요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("소리 따라 걷기")
        .onDisappear {
            task?.cancel()
            engine.stop()
        }
    }

    /// 오차를 도우미가 읽기 쉬운 말로. +는 목표보다 오른쪽을 보고 있다는 뜻이다.
    private func liveWords(_ e: Double) -> String {
        if abs(e) <= 15 { return "목표 쪽을 보고 있어요" }
        if abs(e) >= 135 { return "반대쪽을 보고 있어요" }
        return e > 0 ? "목표보다 오른쪽을 봐요" : "목표보다 왼쪽을 봐요"
    }

    private func say(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        u.rate = 0.5
        speech.speak(u)
    }

    /// 목표와 얼굴 방향의 차이(°, 시계 방향이 +). 고개를 오른쪽으로 돌리면 yaw 가 음수가 되므로
    /// 얼굴 방향(시계 방향) = −yaw 다(2026-09-29 실기기 확인).
    private func headingError() -> Double {
        let facing = -engine.relativeYawDegrees
        var e = facing - goal.bearing
        while e > 180 { e -= 360 }
        while e < -180 { e += 360 }
        return e
    }

    private func start() {
        engine.stimulus = .noise
        engine.algorithm = .HRTFHQ
        engine.followHead = true
        engine.calibrateFront()
        goal = fixed(target)
        samples = []
        result = []
        let began = Date()
        task = Task { @MainActor in
            say("눈을 감고, 소리 나는 쪽으로 몸을 돌려 천천히 걸어가세요.")
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            var nextPing = Date()
            while !Task.isCancelled {
                let t = Date().timeIntervalSince(began)
                if t > Self.walkSeconds + 2.5 { break }
                if Date() >= nextPing {
                    engine.play(bearing: goal.bearing)
                    nextPing = Date().addingTimeInterval(Double(Self.pingEvery) / 1e9)
                }
                samples.append((t, headingError()))
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard !Task.isCancelled else { return }
            say("멈추세요.")
            finish()
        }
    }

    private func finish() {
        task?.cancel()
        task = nil
        let walking = samples.filter { $0.t >= 2.5 }
        guard !walking.isEmpty else { return }
        let firstOn = walking.first { abs($0.error) <= 15 }.map { $0.t - 2.5 }
        let lastFive = walking.filter { $0.t >= (walking.last!.t - 5) }
        let meanLast = lastFive.map { abs($0.error) }.reduce(0, +) / Double(max(lastFive.count, 1))
        let final = walking.last!.error
        let onShare = Double(walking.filter { abs($0.error) <= 15 }.count) / Double(walking.count)
        result = [
            firstOn.map { String(format: "목표 방향을 처음 잡기까지: %.1f초", $0) } ?? "목표 방향(±15°)을 한 번도 못 잡았어요",
            String(format: "목표 방향(±15°) 안에 있던 시간: %.0f%%", onShare * 100),
            String(format: "마지막 5초 평균 차이: %.0f°", meanLast),
            String(format: "끝났을 때 차이: %+.0f°", final),
        ]
        store.add(Trial(experiment: "E7-따라걷기",
                        condition: "목표 \(goal.name)" + (target == .random ? " (무작위)" : ""),
                        expected: String(format: "%.0f°", goal.bearing),
                        answered: String(format: "%+.0f°", final),
                        reactionMs: (firstOn ?? -1) * 1000,
                        note: String(format: "±15° 안 %.0f%% · 마지막5초 평균 %.0f° · 표본 %d",
                                     onShare * 100, meanLast, walking.count)))
    }
}
