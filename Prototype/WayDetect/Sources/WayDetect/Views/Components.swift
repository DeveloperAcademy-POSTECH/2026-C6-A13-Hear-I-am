import SwiftUI
import WayDetectCore

struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String
    var color: Color = .indigo
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit().foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading).padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
    }
}
struct InfoNote: View {
    let text: String
    var symbol = "info.circle"
    var body: some View {
        Label(text, systemImage: symbol).font(.footnote).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
struct DirectionDial: View {
    let remaining: Double
    let active: Bool
    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 10)
            ForEach(1...12, id: \.self) { hour in
                Text("\(hour)").font(.caption.weight(hour % 3 == 0 ? .bold : .regular))
                    .offset(x: sin(Double(hour) * .pi / 6) * 87, y: -cos(Double(hour) * .pi / 6) * 87)
            }
            Image(systemName: "location.north.fill").font(.system(size: 48))
                .foregroundStyle(active ? Color.indigo : .secondary)
                .rotationEffect(.degrees(remaining))
        }.frame(width: 210, height: 210)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("현재 정면 기준 목표 방향")
            .accessibilityValue(active ? "\(Angles.clock(remaining))시 방향" : "확인 중")
    }
}
extension Double {
    var durationText: String {
        let t = max(0, Int(isFinite ? self : 0)); return String(format: "%02d:%02d", t / 60, t % 60)
    }
}
