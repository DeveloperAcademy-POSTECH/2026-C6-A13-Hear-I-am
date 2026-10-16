import SwiftUI
import PoC4Core

struct GuidanceRecordDetail: View {
    let record: GuidanceRecord
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                Label("안내 완료",systemImage:"checkmark.circle.fill").font(.headline).foregroundStyle(Color.hearGreen)
                Text(record.stageName).font(.title.bold())
                Text(record.completedAt,format:.dateTime.locale(Locale(identifier:"ko_KR")).year().month().day().hour().minute()).foregroundStyle(.secondary)
                StageMap(width:record.route.area.width,depth:record.route.area.depth,points:record.route.points,objects:record.route.obstacles)
                    .frame(height:220).accessibilityLabel("완료한 안내의 저장 동선")
                VStack(spacing:18) {
                    metric("안내 시간",record.activeDurationText)
                    Divider()
                    metric("도착한 지점","\(record.reachedPointCount)개 / \(record.reachedPointCount)개")
                    Divider()
                    metric("저장된 동선 길이",String(format:"%.1f m",record.routeLength))
                }.padding(20).background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:20))
                Text("안내 시간은 일시정지와 현장 재확인 시간을 제외해요. 도착한 지점 수에는 출발점을 포함하지 않아요. 동선 길이는 저장된 지점 사이 거리이며 실제 걸은 거리와 다를 수 있어요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }.navigationTitle("완료 기록").navigationBarTitleDisplayMode(.inline)
    }
    private func metric(_ title: String,_ value: String) -> some View {
        HStack {Text(title).foregroundStyle(.secondary);Spacer();Text(value).font(.title3.bold()).monospacedDigit()}
    }
}
