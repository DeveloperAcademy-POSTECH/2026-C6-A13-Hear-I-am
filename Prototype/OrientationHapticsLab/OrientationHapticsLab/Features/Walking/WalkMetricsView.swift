import OrientationCore
import SwiftUI

struct WalkMetricsView: View {
    let snapshot: WalkSnapshot
    let status: String

    var body: some View {
        GroupBox("리셋 이후 이동") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(snapshot.steps)")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                    Text("걸음 · 센서 집계").font(.subheadline)
                    Spacer()
                }
                LabeledContent("추정 이동 거리", value: meters(snapshot.estimatedDistance))
                LabeledContent("추정 전방 좌표", value: signedMeters(snapshot.forwardDisplacement))
                LabeledContent("추정 오른쪽 좌표", value: signedMeters(snapshot.rightDisplacement))
                Text(snapshot.source == .systemEstimate ? "거리 계산: iOS 시스템 추정" : "거리 계산: 1걸음 × 0.65m 추정")
                    .font(.caption).foregroundStyle(.secondary)
                if snapshot.isDisplacementUncertain {
                    Label("회전 또는 방향 자료 누락으로 좌표 오차가 커질 수 있어요.", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text(status).font(.caption).foregroundStyle(.secondary)
                Text("좌표는 몸이 향한 방향으로 앞으로 걸었다는 가정입니다. 음수는 뒤쪽·왼쪽이며, 옆걸음·뒷걸음을 구분하지 못합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private func meters(_ value: Double) -> String { String(format: "%.2f m", value) }
    private func signedMeters(_ value: Double) -> String { String(format: "%+.2f m", value) }
}
