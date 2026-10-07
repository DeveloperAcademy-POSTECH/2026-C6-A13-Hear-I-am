import OrientationCore
import SwiftUI

struct LogsView: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        List {
            if let message = store.storageMessage {
                Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            if store.records.isEmpty {
                ContentUnavailableView("이전 사이클 없음", systemImage: "clock.arrow.circlepath",
                                       description: Text("기준을 다시 리셋하거나 측정을 중지하면 기록됩니다."))
            }
            ForEach(store.records) { record in
                NavigationLink {
                    SessionDetailView(store: store, recordID: record.id)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.startedAt.formatted(date: .abbreviated, time: .standard)).font(.headline)
                        Text("\(record.walk.steps)걸음 · 마지막 \(angleText(record.lastAngleDegrees)) · \(reasonText(record.endReason))")
                            .font(.subheadline)
                        Text(store.completionNote(for: record.id)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("사이클 로그")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: store.exportJSON) { Label("JSON 공유", systemImage: "square.and.arrow.up") }
                    .disabled(store.records.isEmpty)
            }
        }
    }
}

private struct SessionDetailView: View {
    @ObservedObject var store: SessionStore
    let recordID: UUID

    var body: some View {
        ScrollView {
            if let record = store.records.first(where: { $0.id == recordID }) {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("측정 사이클") {
                        VStack(spacing: 10) {
                            LabeledContent("시작", value: record.startedAt.formatted(date: .abbreviated, time: .standard))
                            LabeledContent("종료", value: record.endedAt.formatted(date: .abbreviated, time: .standard))
                            LabeledContent("소요 시간", value: String(format: "%.1f초", record.duration))
                            LabeledContent("종료 이유", value: reasonText(record.endReason))
                            LabeledContent("마지막 방향", value: angleText(record.lastAngleDegrees))
                        }
                    }
                    WalkMetricsView(snapshot: record.walk, status: store.completionNote(for: record.id))
                    GroupBox("신호 요청 기록 \(record.hapticEvents.count)개") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("앱이 신호 요청을 받은 기록입니다. 장치 응답 지연이나 중단으로 실제 출력되지 않을 수 있어요. 착용자가 실제로 인지했는지는 현장에서 확인해야 합니다.")
                                .font(.caption).foregroundStyle(.secondary)
                            if record.hapticEvents.isEmpty {
                                Text("수락된 신호 요청 없음").foregroundStyle(.secondary)
                            }
                            ForEach(record.hapticEvents) { event in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.date.formatted(date: .omitted, time: .standard)).font(.caption)
                                    Text(eventLabel(event))
                                    Text("측정 방향 \(angleText(event.headingDegrees)) · \(event.patternID)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding()
            }
        }
        .navigationTitle("사이클 상세")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func eventLabel(_ event: HapticEventRecord) -> String {
        if event.patternID.hasPrefix("reset") { return "기준 방향 리셋 신호" }
        return "\(angleText(event.triggerAngleDegrees)) \(event.patternID.hasPrefix("preview") ? "체험" : "도달") 신호"
    }
}

private func reasonText(_ reason: SessionEndReason) -> String {
    switch reason {
    case .reset: "다음 기준 리셋"
    case .stopped: "측정 중지"
    case .appInterrupted: "앱 또는 방향 측정 중단"
    }
}

private func angleText(_ value: Double) -> String {
    abs(value) < 0.5 ? "정면 0°" : "\(value < 0 ? "왼쪽" : "오른쪽") \(Int(abs(value).rounded()))°"
}
