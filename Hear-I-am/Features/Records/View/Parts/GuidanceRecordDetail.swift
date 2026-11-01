import SwiftUI
import HearIAmCore

struct GuidanceRecordDetail: View {
    let record: GuidanceRecord
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                HStack {
                    Text(record.stageName).font(.title2.bold())
                    Spacer()
                    Label("완료",systemImage:"checkmark.circle.fill").font(.subheadline).foregroundStyle(Color.hearGreen)
                }
                Text(record.completedAt.formatted(.dateTime.locale(Locale(identifier:"ko_KR")).year().month().day().hour().minute()))
                    .font(.subheadline).foregroundStyle(.secondary)
                if let replay=record.replay {
                    GuidanceReplayView(record:record,replay:replay)
                } else {legacySummary}
            }.padding(20)
        }.navigationTitle("안내 기록").navigationBarTitleDisplayMode(.inline)
    }
    private var legacySummary: some View {
        VStack(alignment:.leading,spacing:20) {
            StageMap(width:record.route.area.width,depth:record.route.area.depth,points:record.route.points,objects:record.route.obstacles,dangerZones:record.route.dangerZones)
                .frame(height:220).accessibilityLabel("완료한 안내의 저장 동선")
            Label("이 기록에는 실제 이동 위치가 저장되어 있지 않아요.",systemImage:"clock.badge.questionmark")
                .font(.subheadline).foregroundStyle(.secondary)
            VStack(spacing:18) {
                metric("안내 시간",record.activeDurationText)
                Divider()
                metric("도착한 지점","\(record.reachedPointCount)개 / \(record.reachedPointCount)개")
                Divider()
                metric("표준 경로 길이",String(format:"%.1f m",record.routeLength))
            }.padding(20).background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:20))
            Text("안내 시간은 일시정지와 현장 재확인 시간을 제외해요. 동선 길이는 저장된 지점 사이 거리이며 실제 걸은 거리와 다를 수 있어요.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func metric(_ title: String,_ value: String) -> some View {
        HStack {Text(title).foregroundStyle(.secondary);Spacer();Text(value).font(.title3.bold()).monospacedDigit()}
    }
}
