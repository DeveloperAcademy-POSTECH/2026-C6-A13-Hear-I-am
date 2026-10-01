import SwiftUI
import AVFoundation

/// **테스트 1 · 소리 방향 (E7)** — 무대 평면 8방향에 소리를 놓고 어느 쪽인지 맞힌다.
///
/// 두 라운드를 앱이 차례로 돌린다. 1라운드는 기본값(좌우 팬), 2라운드는 HRTF 고품질.
/// 기본값이 3D가 아니라는 문서 내용이 귀로도 갈리는지 보려는 것이다.
/// 비교 기준은 일반 HRTF 연구의 16~22°다. 그보다 나쁘면 공간 음향은 주 출력에서 뺀다.
struct SpatialView: View {
    @EnvironmentObject private var store: TrialStore
    @StateObject private var engine = SpatialEngine()

    private enum Phase { case setup, round(Int), done }

    private static let perRound = 16

    /// 한 라운드: 렌더링 방식 + 화면 이름.
    /// 삐·쏴는 좌우 팬 → HRTF 두 라운드, 높낮이 약속은 한 라운드(좌우 팬, 머리 따라가지 않음).
    private var rounds: [(algorithm: AVAudio3DMixingRenderingAlgorithm, name: String)] {
        switch engine.stimulus {
        case .code: return [(.equalPowerPanning, "높낮이 약속 (앞 높음 · 뒤 낮음)")]
        case .tone, .noise: return [(.equalPowerPanning, "기본 소리 (좌우만)"), (.HRTFHQ, "3D 소리 (HRTF)")]
        }
    }

    /// 기록에 남는 조건 이름. 처음 판(삐)과 이어지도록 삐는 예전 이름 그대로 쓴다.
    private func condition(_ r: Int) -> String {
        baseCondition(r) + (head == .natural ? " · \(Head.natural.rawValue)" : "")
    }

    private func baseCondition(_ r: Int) -> String {
        switch engine.stimulus {
        case .tone: return rounds[r].algorithm.korean + (fourWay ? " · 4방향" : "")
        case .noise: return "쏴 · \(rounds[r].algorithm.korean)" + (fourWay ? " · 4방향" : "")
        case .code: return "높낮이 약속" + (fourWay ? " · 4방향" : "")
        }
    }

    private static func isDiagonal(_ name: String) -> Bool {
        (name.hasPrefix("앞") || name.hasPrefix("뒤")) && name.count > 1
    }

    /// 한 라운드 16번: 앞 5 · 뒤 5 · 왼쪽 3 · 오른쪽 3 을 섞는다.
    private static func fourWayPlan() -> [Int] {
        func idx(_ n: String) -> Int { directions.firstIndex { $0.name == n }! }
        let plan = Array(repeating: idx("앞"), count: 5) + Array(repeating: idx("뒤"), count: 5)
            + Array(repeating: idx("왼쪽"), count: 3) + Array(repeating: idx("오른쪽"), count: 3)
        return plan.shuffled()
    }

    /// 나침반 배치 순서(3×3, 가운데는 나). 각도는 앞=0, 시계 방향.
    private static let compass: [(name: String, bearing: Double)?] = [
        ("앞왼쪽", 315), ("앞", 0), ("앞오른쪽", 45),
        ("왼쪽", 270), nil, ("오른쪽", 90),
        ("뒤왼쪽", 225), ("뒤", 180), ("뒤오른쪽", 135),
    ]
    private static let directions = compass.compactMap { $0 }

    @State private var phase: Phase = .setup
    @State private var presented: Int?
    @State private var presentedAt = Date()
    @State private var count = 0
    /// 네 방향만(앞·뒤·왼쪽·오른쪽). 목표가 “앞뒤좌우 구분”이라 대각선은 뺀다.
    /// 8방향 무작위로는 한 라운드에 앞·뒤가 5번 안팎밖에 안 나와서, 앞·뒤를 더 자주 낸다.
    @State private var fourWay = true
    /// 고개를 고정하고 하나, 자연스럽게 움직이며 하나. 무용수는 춤추며 고개가 어차피 움직이므로
    /// 그 움직임이 앞뒤 구분을 돕는지 본다(찾으려고 일부러 돌리는 것과는 다르다).
    enum Head: String, CaseIterable, Identifiable {
        case still = "고개 고정", natural = "고개 자연스럽게"
        var id: String { rawValue }
    }
    @State private var head: Head = .still
    @State private var queue: [Int] = []
    /// 자동 확인(고개 추적이 맞게 되나). 화면을 못 보는 자세라 음성으로 안내한다.
    @State private var checkTask: Task<Void, Never>?
    @State private var checkStatus = ""
    @State private var speech = AVSpeechSynthesizer()

    var body: some View {
        Group {
            switch phase {
            case .setup: setup
            case .round(let r): round(r)
            case .done: done
            }
        }
        .navigationTitle("1 소리 방향")
        .onDisappear { engine.stop() }
    }

    // MARK: 준비

    private var setup: some View {
        List {
            Section {
                HowToCard(what: "AirPods 소리만 듣고 방향을 맞히나", steps: [
                    "AirPods를 끼고 ‘소리 켜기’를 눌러요",
                    "정면을 보고 ‘지금이 정면’을 눌러요",
                    "‘소리 확인’으로 방향이 맞게 들리는지 먼저 봐요",
                    "눈을 감고, 들린 방향을 나침반에서 눌러요",
                    "기본 소리 16번 → 3D 소리 16번, 앱이 알아서 바꿔요",
                ])
            }
            Section {
                Picker("소리 종류", selection: $engine.stimulus) {
                    ForEach(SpatialEngine.Stimulus.allCases) { Text($0.short).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(stimulusHelp).font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("무슨 소리로")
            }
            Section {
                Picker("고개", selection: $head) {
                    ForEach(Head.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(head == .still
                     ? "고개를 움직이지 않고 들어요."
                     : "음악에 맞춰 까딱이듯 자연스럽게 움직여요. 소리를 찾으려고 일부러 돌리지는 마세요.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("고개")
            }
            Section {
                Toggle("앞·뒤·왼쪽·오른쪽 네 방향만", isOn: $fourWay)
                Text(fourWay ? "대각선은 빼고, 앞·뒤를 더 자주 내요(16번 중 앞 5 · 뒤 5)." : "여덟 방향을 무작위로 내요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("준비") {
                Button {
                    engine.isRunning ? engine.stop() : engine.start()
                } label: {
                    ResultRow(name: engine.isRunning ? "소리 켜짐" : "소리 켜기",
                              value: engine.isRunning ? "끄기" : "켜기")
                }
                ResultRow(name: "머리 방향 읽기",
                          value: engine.headphonesConnected ? "됨" : "아직",
                          good: engine.headphonesConnected)
                Button("지금이 정면") { engine.calibrateFront() }
                    .disabled(!engine.isRunning)
                if engine.headphonesConnected {
                    ResultRow(name: "정면에서 머리가 돈 정도", value: "\(Int(engine.relativeYawDegrees))°")
                }
                if let err = engine.lastError {
                    Text(err).font(.caption).foregroundStyle(.orange)
                }
            }
            Section {
                HStack(spacing: 8) {
                    ForEach([("앞", 0.0), ("오른쪽", 90.0), ("뒤", 180.0), ("왼쪽", 270.0)], id: \.0) { name, bearing in
                        Button(name) { engine.play(bearing: bearing) }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(!engine.isRunning)
                Text("① 고개를 고정하고 ‘오른쪽’ → 오른쪽 귀에서 들려야 해요\n② 고개를 오른쪽으로 돌린 채 ‘오른쪽’ → 정면에서 들려야 해요\n둘 중 하나라도 반대면 시작하지 말고 알려 주세요.")
                    .font(.footnote)
                if checkTask == nil {
                    HStack {
                        Button("자동 확인 · 고개 오른쪽") { startHeadCheck(toRight: true) }
                        Button("자동 확인 · 고개 왼쪽") { startHeadCheck(toRight: false) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!engine.isRunning || !engine.headphonesConnected)
                } else {
                    Button("자동 확인 멈추기") { stopHeadCheck() }.buttonStyle(.bordered)
                }
                Text("정면을 보고 누르면 음성으로 안내해요. 말한 쪽으로 고개를 돌리면 3초 뒤 ‘하나’, ‘둘’ 소리가 나요. 하나와 둘이 각각 앞·옆·뒤 중 어디서 들렸는지 기억해 두세요.")
                    .font(.caption).foregroundStyle(.secondary)
                if !checkStatus.isEmpty {
                    Text(checkStatus).font(.caption.monospacedDigit())
                }
            } header: {
                Text("시작 전에 소리 확인")
            }
            Section {
                Text("제어 센터의 ‘공간 음향’ 설정(끔 · 고정 · 머리 추적)을 메모하고, 테스트 중엔 바꾸지 마세요.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button {
                    count = 0
                    phase = .round(0)
                    engine.algorithm = rounds[0].algorithm
                    // 높낮이 약속은 몸 기준 약속이라 머리를 따라가지 않는다
                    engine.followHead = engine.stimulus != .code
                    queue = Self.fourWayPlan()
                    afterPause { present() }
                } label: {
                    Text("시작").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundStyle(.black)
                .disabled(!engine.isRunning)
            }
        }
    }

    private var stimulusHelp: String {
        switch engine.stimulus {
        case .tone: return "처음에 했던 소리예요. 한 음이라 앞뒤 단서가 적어요."
        case .noise: return "‘쏴’ 하는 넓은 소리예요. 앞뒤를 가르는 높은 주파수가 들어 있어서 앞뒤가 나아질 수 있어요."
        case .code: return "위치 대신 약속이에요. 왼쪽·오른쪽은 귀로, 앞은 높은 음 · 옆은 중간 음 · 뒤는 낮은 음. 고개를 돌려도 소리가 따라 돌지 않아요."
        }
    }

    // MARK: 라운드

    private func round(_ r: Int) -> some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(rounds.count > 1 ? "\(r + 1)라운드 · \(rounds[r].name)" : rounds[r].name).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(min(count + 1, Self.perRound))/\(Self.perRound)").monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(count), total: Double(Self.perRound)).tint(.yellow)
            }
            Text("어느 쪽에서 들렸어요?").font(.title3.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(Self.compass.indices, id: \.self) { i in
                    if let d = Self.compass[i], !(fourWay && Self.isDiagonal(d.name)) {
                        Button { answer(d.name) } label: {
                            Text(d.name).font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 64)
                        }
                        .buttonStyle(.bordered)
                    } else if Self.compass[i] != nil {
                        // 네 방향 모드의 대각선 자리는 비워 둔다
                        Color.clear.frame(maxWidth: .infinity, minHeight: 64)
                    } else {
                        Image(systemName: "person.fill")
                            .font(.title)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 64)
                    }
                }
            }
            Button {
                if let i = presented { engine.play(bearing: Self.directions[i].bearing) }
            } label: {
                Label("다시 듣기", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
    }

    // MARK: 결과

    private var done: some View {
        let rows = store.trials(of: "E7")
        return List {
            ForEach(rounds.indices, id: \.self) { r in
                let rs = rows.filter { $0.condition == condition(r) }.suffix(Self.perRound)
                Section(rounds[r].name) {
                    if let s = SpatialStats(Array(rs)) {
                        ResultRow(name: "방향 오차 (보통)", value: "\(Int(s.medianError))°", good: s.medianError <= 22)
                        ResultRow(name: "앞뒤를 헷갈림", value: "\(s.frontBack)번 / \(s.n)번")
                    }
                }
            }
            Section {
                Text("오차가 22°보다 크면 AirPods로 방향을 알려 주기 어려워요. 앞뒤를 자주 헷갈리면 앞·뒤는 소리 위치 말고 다른 방법으로 알려야 해요.")
                    .font(.footnote)
                Button("처음부터 다시") {
                    engine.followHead = true
                    phase = .setup
                }
            }
        }
    }

    // MARK: 자동 확인

    private func say(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        u.rate = 0.5
        speech.speak(u)
    }

    private func stopHeadCheck() {
        checkTask?.cancel()
        checkTask = nil
        speech.stopSpeaking(at: .immediate)
    }

    /// 말한 쪽으로 고개를 돌리면 3초 뒤 ‘하나’ = 고개를 돌린 쪽 음원, ‘둘’ = 반대쪽 음원을 낸다.
    /// 고개 추적이 맞으면 하나는 **앞**, 둘은 **뒤**에서 들려야 한다. 둘 다 옆이면 추적이 안 먹은 것,
    /// 하나가 뒤·둘이 앞이면 부호가 거꾸로다. 고개를 돌린 쪽과 각도의 부호를 함께 기록한다.
    private func startHeadCheck(toRight: Bool) {
        engine.followHead = true
        engine.calibrateFront()
        let sideWord = toRight ? "오른쪽" : "왼쪽"
        checkStatus = "고개를 \(sideWord)으로 돌리는 중…"
        checkTask = Task { @MainActor in
            say("정면을 기준으로 잡았어요. 몸은 그대로, 고개만 \(sideWord)으로 90도 돌려 주세요.")
            // 90° 근처(82~98°)에 오면 "멈추세요". 지나치면 "조금 돌아오세요".
            // 멈춘 뒤 2초 동안 그 범위에 머물러야 소리를 낸다 — 첫 시도는 115°까지 지나쳤다.
            let started = Date()
            var warnedOver = false
            waiting: while !Task.isCancelled {
                let yaw = abs(engine.relativeYawDegrees)
                checkStatus = String(format: "지금 고개 %+.0f°", engine.relativeYawDegrees)
                if Date().timeIntervalSince(started) > 40 {
                    say("시간이 지나서 멈췄어요. 다시 눌러 주세요.")
                    checkTask = nil
                    return
                }
                if yaw > 100 {
                    if !warnedOver { say("너무 많이 돌렸어요. 조금 돌아오세요."); warnedOver = true }
                } else if yaw >= 82 {
                    say("멈추세요.")
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    let settled = abs(engine.relativeYawDegrees)
                    if settled >= 75 && settled <= 105 { break waiting }
                    say(settled > 105 ? "조금 돌아오세요." : "조금 더 돌려 주세요.")
                    warnedOver = false
                } else {
                    warnedOver = false
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard !Task.isCancelled else { return }
            say("좋아요. 그대로 계세요.")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let held = engine.relativeYawDegrees
            let turned: Double = toRight ? 90 : 270
            let opposite: Double = toRight ? 270 : 90
            say("하나")
            try? await Task.sleep(nanoseconds: 700_000_000)
            engine.play(bearing: turned)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            say("둘")
            try? await Task.sleep(nanoseconds: 700_000_000)
            engine.play(bearing: opposite)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            say("하나와 둘이 각각 앞, 옆, 뒤 중 어디서 들렸는지 알려 주세요.")
            checkStatus = String(format: "고개 %@ · %+.0f° 에서 확인함 · 하나 = %@ 음원(앞이어야 맞음), 둘 = 반대쪽 음원(뒤여야 맞음)",
                                 sideWord, held, sideWord)
            store.add(Trial(experiment: "E7-고개확인",
                            condition: "\(engine.stimulus.short) · 고개 \(sideWord)",
                            expected: "하나 앞 · 둘 뒤",
                            answered: "",
                            reactionMs: 0,
                            note: String(format: "yaw %+.1f · 하나=%@(%.0f) 둘=반대(%.0f) · followHead %@",
                                         held, sideWord, turned, opposite, engine.followHead ? "켬" : "끔")))
            checkTask = nil
        }
    }

    // MARK: 진행

    private func present() {
        if fourWay, queue.isEmpty { queue = Self.fourWayPlan() }
        let i = fourWay ? queue.removeFirst() : Int.random(in: Self.directions.indices)
        presented = i
        presentedAt = Date()
        engine.play(bearing: Self.directions[i].bearing)
    }

    private func answer(_ name: String) {
        guard let i = presented, case .round(let r) = phase,
              let j = Self.directions.firstIndex(where: { $0.name == name }) else { return }
        let diff = abs(Self.directions[i].bearing - Self.directions[j].bearing)
        store.add(Trial(experiment: "E7",
                        condition: condition(r),
                        expected: Self.directions[i].name,
                        answered: name,
                        reactionMs: Date().timeIntervalSince(presentedAt) * 1000,
                        note: String(format: "%.0f", min(diff, 360 - diff))))
        presented = nil
        count += 1
        if count < Self.perRound {
            afterPause { present() }
        } else if r + 1 < rounds.count {
            count = 0
            engine.algorithm = rounds[r + 1].algorithm
            queue = Self.fourWayPlan()
            phase = .round(r + 1)
            afterPause { present() }
        } else {
            phase = .done
        }
    }
}

/// 소리 방향 결과 요약. 평균 대신 중앙값을 쓴다.
struct SpatialStats {
    let n: Int
    let medianError: Double
    let frontBack: Int

    init?(_ rows: [Trial]) {
        guard !rows.isEmpty else { return nil }
        n = rows.count
        medianError = TrialStore.percentile(rows.compactMap { Double($0.note) }, 0.5) ?? 0
        frontBack = rows.filter(Self.isFrontBack).count
    }

    /// 앞뒤 혼동 — 좌우는 맞았는데 앞뒤가 뒤집힌 경우
    private static func isFrontBack(_ t: Trial) -> Bool {
        let mirror = ["앞": "뒤", "뒤": "앞", "앞왼쪽": "뒤왼쪽", "뒤왼쪽": "앞왼쪽",
                      "앞오른쪽": "뒤오른쪽", "뒤오른쪽": "앞오른쪽"]
        return mirror[t.expected] == t.answered
    }
}

/// 답한 뒤 다음 문제를 잠깐 쉬었다 내보낸다.
@MainActor
func afterPause(_ action: @escaping @MainActor () -> Void) {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 700_000_000)
        action()
    }
}
