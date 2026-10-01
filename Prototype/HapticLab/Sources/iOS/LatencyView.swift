import SwiftUI

/// **테스트 9 · 전달 속도 (E8)**
///
/// 시험 신호를 100번 보내고 **왕복 시간**을 잰다. 누르면 알아서 100번 보내고 멈춘다.
/// iPhone 과 Watch 의 시계가 서로 다르므로 편도 지연을 직접 잴 수는 없다 —
/// 대신 왕복(iPhone 시계만으로)과 Watch 안의 처리 시간을 따로 남긴다.
///
/// 목표값은 RunPacer 의 **100ms 미만**. 평균만 보지 않고 느린 쪽 5%(95백분위)를 같이 본다.
struct LatencyView: View {
    @EnvironmentObject private var link: PhoneLink
    @EnvironmentObject private var store: TrialStore

    private static let total = 100
    private static let periodMs: UInt64 = 300

    @State private var task: Task<Void, Never>?
    @State private var sent = 0

    private var running: Bool { task != nil }

    var body: some View {
            List {
                Section {
                    HowToCard(what: "폰에서 보낸 신호가 시계에 얼마나 빨리 닿나", steps: [
                        "시계에서 HapticLab → ‘폰 신호 받기’를 열어 둬요",
                        "‘측정 시작’을 누르면 약한 톡이 100번 와요 (30초쯤)",
                        "끝나면 아래 결과를 봐요",
                    ])
                    ConnectionBanner()
                }

                Section {
                    if running {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("보내는 중 \(sent)/\(Self.total)").monospacedDigit()
                            ProgressView(value: Double(sent), total: Double(Self.total)).tint(.yellow)
                        }
                        Button("멈추기", role: .destructive) { stop() }
                    } else {
                        Button { start() } label: {
                            Text(link.summary == nil ? "측정 시작" : "다시 측정")
                                .font(.headline).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.yellow)
                        .foregroundStyle(.black)
                        .disabled(!link.isReachable)
                    }
                }

                if let s = link.summary {
                    Section("결과 · \(s.n)번") {
                        let ok = s.median < 100 && s.p95 <= 200
                        Label(ok ? "공연 중 신호로 쓸 만한 속도예요" : "가끔 너무 늦어요",
                              systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(ok ? .green : .orange)
                            .font(.headline)
                        ResultRow(name: "보통 걸린 시간", value: "\(Int(s.median))ms", good: s.median < 100)
                        ResultRow(name: "가끔 느릴 때 (느린 5%)", value: "\(Int(s.p95))ms", good: s.p95 <= 200)
                        ResultRow(name: "가장 느렸을 때", value: "\(Int(s.max))ms")
                        ResultRow(name: "못 간 신호", value: "\(link.failedCount + link.droppedCount)번",
                                  good: link.failedCount + link.droppedCount == 0)
                    }
                    Section {
                        Text("폰→시계→폰 왕복 시간이에요. 목표는 보통 100ms 미만, 느린 5%도 200ms 이하.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("9 전달 속도")
    }

    private func start() {
        link.reset()
        sent = 0
        task = Task {
            while !Task.isCancelled && sent < Self.total {
                link.send(GuideCommand(signal: .heartbeat, validForMs: 5000, isProbe: true))
                sent += 1
                try? await Task.sleep(nanoseconds: Self.periodMs * 1_000_000)
            }
            // 마지막 회신이 돌아올 틈을 준다
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            finish()
        }
    }

    private func stop() {
        task?.cancel()
        finish()
    }

    private func finish() {
        task = nil
        guard let s = link.summary else { return }
        store.add(Trial(experiment: "E8",
                        condition: "\(s.n)번",
                        expected: "<100ms",
                        answered: "\(Int(s.median))ms",
                        reactionMs: s.p95,
                        note: "max \(Int(s.max))ms 실패 \(link.failedCount) 버림 \(link.droppedCount)"))
    }
}
