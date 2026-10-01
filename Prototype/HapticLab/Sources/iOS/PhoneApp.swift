import SwiftUI

/// 지금은 **카메라 + 소리 따라 걷기(S2) 하나만** 띄운다(사용자 요청, 2026-10-01).
/// 다른 테스트 화면의 코드는 지우지 않고 남겨 두었다 — 목록(`TestListView`)을 다시 루트로 두면 돌아온다.
@main
struct HapticLabApp: App {
    @StateObject private var store = TrialStore()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                StageView(withSound: true)
            }
            .environmentObject(store)
        }
    }
}

// MARK: - 테스트 목록

/// 첫 화면. 번호는 테스트 안내 페이지의 번호와 같다.
/// 시계가 없어도 할 수 있는 것을 위에 둔다.
struct TestListView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { SpatialView() } label: {
                        TestRow(number: "1", title: "소리 방향", detail: "AirPods 소리로 8방향을 맞히나")
                    }
                    NavigationLink { BeaconWalkView() } label: {
                        TestRow(number: "1+", title: "소리 따라 걷기", detail: "소리 나는 쪽으로 몸을 돌려 걸어가나")
                    }
                    NavigationLink { SoundSignalView() } label: {
                        TestRow(number: "2", title: "소리 신호 맞히기", detail: "왼쪽·오른쪽·뒤·도착·정지를 소리로")
                    }
                    NavigationLink { AirPodsOutView() } label: {
                        TestRow(number: "3", title: "AirPods 빼 보기", detail: "빠지면 소리가 스피커로 새나")
                    }
                    NavigationLink { RemoteView(output: .airpods) } label: {
                        TestRow(number: "4", title: "소리로 목표까지", detail: "두 사람 · 폰 든 사람이 신호를 보내요")
                    }
                } header: {
                    Text("시계 없이 · 폰 + AirPods")
                }
                Section {
                    NavigationLink { StageView() } label: {
                        TestRow(number: "S1", title: "무대 위치 찾기", detail: "세운 폰 카메라로 사람 위치를 잡나")
                    }
                    NavigationLink { StageView(withSound: true) } label: {
                        TestRow(number: "S2", title: "카메라 + 소리 따라 걷기", detail: "목표 자리에서 나는 소리로 걸어가나")
                    }
                } header: {
                    Text("카메라 (세워 둔 폰)")
                }
                Section {
                    TestRow(number: "5–8", title: "진동 테스트", detail: "시계의 HapticLab 앱에서 해요")
                    NavigationLink { LatencyView() } label: {
                        TestRow(number: "9", title: "전달 속도", detail: "폰→시계 신호가 얼마나 빨리 닿나")
                    }
                    NavigationLink { RemoteView(output: .watch) } label: {
                        TestRow(number: "10", title: "진동으로 목표까지", detail: "두 사람 · 시계로 신호를 보내요")
                    }
                } header: {
                    Text("시계가 있을 때")
                }
            }
            .navigationTitle("HapticLab")
        }
    }
}

struct TestRow: View {
    let number: String
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.subheadline.weight(.bold))
                .frame(minWidth: 30, minHeight: 30)
                .background(Capsule().fill(.yellow))
                .foregroundStyle(.black)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 공용 조각

/// 화면 맨 위 "하는 법". 처음엔 펼쳐 두고, 익숙해지면 접는다.
struct HowToCard: View {
    let what: String
    let steps: [String]
    @State private var open = true

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(steps.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(i + 1)")
                            .font(.caption.weight(.bold))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(.yellow))
                            .foregroundStyle(.black)
                        Text(steps[i]).font(.subheadline)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("하는 법").font(.caption).foregroundStyle(.secondary)
                Text(what).font(.headline)
            }
        }
    }
}

/// 시계와 이어졌는지, 안 됐다면 **무엇을 하면 되는지**를 한 줄로.
struct ConnectionBanner: View {
    @EnvironmentObject private var link: PhoneLink

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: link.isReachable ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                .font(.title3)
                .foregroundStyle(link.isReachable ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                if let hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
    }

    private var title: String {
        if link.isReachable { return "시계 연결됨" }
        if !link.isPaired { return "짝지은 시계가 없어요" }
        if !link.isInstalled { return "시계에 HapticLab이 없어요" }
        return "시계가 아직 안 보여요"
    }

    private var hint: String? {
        if link.isReachable { return nil }
        if !link.isPaired { return "iPhone의 Watch 앱에서 시계를 먼저 연결해요" }
        if !link.isInstalled { return "iPhone Watch 앱 → 사용 가능한 앱 → HapticLab 설치" }
        return "시계에서 HapticLab → ‘폰 신호 받기’를 열어 두세요"
    }
}

/// 결과 한 줄: 이름 · 값 · (선택) 판정 색
struct ResultRow: View {
    let name: String
    let value: String
    var good: Bool?
    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(good.map { $0 ? Color.green : Color.orange } ?? Color.primary)
        }
    }
}

// MARK: - 결과 탭

struct ResultsTab: View {
    @EnvironmentObject private var store: TrialStore
    @EnvironmentObject private var link: PhoneLink
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                Section("1 소리 방향") {
                    let rows = store.trials(of: "E7")
                    let rounds = Array(Set(rows.map(\.condition))).sorted()
                    if rows.isEmpty {
                        Text("아직 안 했어요").foregroundStyle(.secondary)
                    }
                    ForEach(rounds, id: \.self) { r in
                        // 마지막 한 판(16번)만 본다. 지난 판과 섞으면 조건이 다른 결과가 합쳐진다.
                        let rs = Array(rows.filter { $0.condition == r }.suffix(16))
                        if let s = SpatialStats(rs) {
                            ResultRow(name: r, value: "오차 \(Int(s.medianError))° · 앞뒤 \(s.frontBack)번",
                                      good: s.medianError <= 22)
                        }
                    }
                }
                Section("2 소리 신호 맞히기") {
                    let rows = store.trials(of: "E1-AirPods")
                    if rows.isEmpty { Text("아직 안 했어요").foregroundStyle(.secondary) }
                    ForEach(Array(Set(rows.map(\.condition))).sorted(), id: \.self) { c in
                        let rs = rows.filter { $0.condition == c }
                        let hit = rs.filter(\.isCorrect).count
                        ResultRow(name: c, value: "\(hit * 100 / rs.count)% · \(rs.count)번",
                                  good: hit * 10 >= rs.count * 9)
                    }
                }
                Section("3 AirPods 빼 보기") {
                    let rows = store.trials(of: "E9-AirPods")
                    if rows.isEmpty { Text("아직 안 했어요").foregroundStyle(.secondary) }
                    ForEach(rows.suffix(2)) { t in
                        ResultRow(name: "\(t.condition) 뺐을 때", value: t.answered,
                                  good: t.answered == "폰 스피커에서 나와요" ? false : nil)
                    }
                }
                Section("9 전달 속도") {
                    if let s = link.summary {
                        ResultRow(name: "보통", value: "\(Int(s.median))ms", good: s.median < 100)
                        ResultRow(name: "가끔 느릴 때", value: "\(Int(s.p95))ms", good: s.p95 <= 200)
                        ResultRow(name: "가장 느림", value: "\(Int(s.max))ms")
                    } else {
                        Text("아직 안 했어요").foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("테스트 5~8은 시계에서 해요. 결과도 시계의 ‘지난 결과’에 있어요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    ShareLink(item: store.tsv,
                              preview: SharePreview("HapticLab 기록.tsv")) {
                        Label("기록 파일로 보내기", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.trials.isEmpty)
                    Button("기록 모두 지우기", role: .destructive) { confirmClear = true }
                        .disabled(store.trials.isEmpty)
                } footer: {
                    Text("표 파일(TSV)로 보내요. 칸을 탭으로 나눠서 설명에 쉼표가 있어도 안 깨져요.")
                }
            }
            .navigationTitle("결과")
            .confirmationDialog("폰에 있는 기록을 모두 지울까요?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("지우기", role: .destructive) { store.clear(); link.reset() }
            }
        }
    }
}
