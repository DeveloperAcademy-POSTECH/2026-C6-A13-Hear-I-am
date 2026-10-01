import SwiftUI

/// **폰 신호 받기** — 테스트 9(전달 속도)·10(진동으로 목표까지)에서 쓴다.
/// iPhone(운영자)이 보내는 지시를 받아 재생한다. 손목에 차고 이 화면을 열어 둔다.
/// WatchConnectivity 는 시계 앱이 앞에 떠 있어야 닿으므로, 이 화면을 벗어나지 않게 안내한다.
struct ReceiverView: View {
    @EnvironmentObject private var player: HapticPlayer
    @StateObject private var model = ReceiverModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                let connected = model.link?.isReachable == true
                HStack(spacing: 8) {
                    Image(systemName: connected ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                        .font(.title3)
                        .foregroundStyle(connected ? .green : .orange)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(connected ? "폰과 연결됨" : "폰을 찾는 중").font(.headline)
                        Text(connected ? "이 화면을 켜 둔 채로 두세요" : "폰에서 HapticLab을 열어 두세요")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                if let link = model.link {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("방금 받은 신호").font(.caption2).foregroundStyle(.secondary)
                        if let s = player.nowPlaying ?? link.lastSignal {
                            Label(s.korean, systemImage: s.symbol).font(.title3.weight(.semibold))
                            if player.nowPlaying != nil {
                                Text("반복 중").font(.caption2).foregroundStyle(.yellow)
                            }
                        } else {
                            Text("조용함 — 잘 가고 있어요").font(.footnote)
                        }
                    }
                    Text("받은 신호 \(link.received) · 늦어서 버림 \(link.dropped)")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Divider()

                Toggle(isOn: Binding(
                    get: { model.watchdog?.isAlive ?? false },
                    set: { on in on ? model.watchdog?.start() : model.watchdog?.stop() }
                )) {
                    Text("끊김 감시").font(.footnote.weight(.semibold))
                }
                Text("켜면 4.5초마다 약한 톡이 와요. 폰 소식이 3초 넘게 없으면 시계가 스스로 정지 진동을 내요.")
                    .font(.caption2).foregroundStyle(.secondary)

                Button("숫자 초기화") {
                    model.link?.resetCounters()
                    player.resetCounters()
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
        .navigationTitle("폰 신호 받기")
        .onAppear { model.attach(player: player) }
    }
}

@MainActor
final class ReceiverModel: ObservableObject {
    @Published var link: WatchLink?
    @Published var watchdog: Watchdog?

    func attach(player: HapticPlayer) {
        guard link == nil else { return }
        let dog = Watchdog(player: player)
        watchdog = dog
        link = WatchLink(player: player, watchdog: dog)
    }
}

/// **지난 결과** — 앱을 꺼도 남는다. 테스트별로 몇 번 했고 얼마나 맞혔는지.
struct ResultsView: View {
    @EnvironmentObject private var store: TrialStore
    @State private var confirmClear = false

    private static let names: [(id: String, name: String)] = [
        ("E6-1", "5 진동 간격"),
        ("E6-2-세기", "6 진동 세기 · 세기"),
        ("E6-2-무게", "6 진동 세기 · 무게"),
        ("E1", "7 신호 맞히기 · 가만히"),
        ("E2-걷기", "7 신호 맞히기 · 걸으며"),
        ("E2-안무", "7 신호 맞히기 · 춤추며"),
        ("E5", "8 계속 울리나"),
    ]

    var body: some View {
        List {
            let shown = Self.names.filter { !store.trials(of: $0.id).isEmpty }
            if shown.isEmpty {
                Text("아직 결과가 없어요").foregroundStyle(.secondary)
            }
            ForEach(shown, id: \.id) { item in
                let rows = store.trials(of: item.id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.footnote.weight(.semibold))
                    Text(summary(item.id, rows)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !shown.isEmpty {
                Button(confirmClear ? "한 번 더 누르면 지워요" : "결과 모두 지우기", role: .destructive) {
                    if confirmClear { store.clear(); confirmClear = false } else { confirmClear = true }
                }
                .font(.caption)
            }
        }
        .navigationTitle("지난 결과")
    }

    private func summary(_ id: String, _ rows: [Trial]) -> String {
        switch id {
        case "E5":
            return rows.suffix(2).map { "\($0.condition): \($0.note)" }.joined(separator: " · ")
        case "E6-1":
            let bad = rows.filter { !$0.isCorrect }.count
            return "\(rows.count)번 · 뭉개짐 \(bad)번"
        default:
            let hit = rows.filter(\.isCorrect).count
            return "\(rows.count)번 중 \(hit)번 맞힘 (\(hit * 100 / max(rows.count, 1))%)"
        }
    }
}
