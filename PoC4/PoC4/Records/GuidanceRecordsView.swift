import SwiftUI
import PoC4Core

struct GuidanceRecordsView: View {
    @ObservedObject var library: StageLibrary
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    Text("완료한 안내를 돌아봐요").font(.title2.bold())
                    Text("마지막 지점에 도착한 뒤 종료한 안내만 기록돼요.").font(.subheadline).foregroundStyle(.secondary)
                    if let error=library.recordError {
                        Text(error).foregroundStyle(.red)
                        Button("다시 불러오기") {Task {await library.refreshGuidanceRecords()}}
                    }
                    if library.guidanceRecords.isEmpty && library.recordError == nil {
                        ContentUnavailableView("완료한 안내가 아직 없어요",systemImage:"clock",description:Text("저장한 무대로 안내를 시작하고\n마지막 도착 안내 후 종료해주세요."))
                    }
                    ForEach(library.guidanceRecords) { record in
                        NavigationLink { GuidanceRecordDetail(record:record) } label: {
                            VStack(alignment:.leading,spacing:14) {
                                HStack(alignment:.top) {
                                    VStack(alignment:.leading,spacing:7) {
                                        Text(record.stageName).font(.headline)
                                        Text(record.completedAt,format:.dateTime.locale(Locale(identifier:"ko_KR")).year().month().day().hour().minute())
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName:"checkmark.circle.fill").foregroundStyle(Color.hearGreen)
                                }
                                HStack {
                                    Label(duration(record.activeSeconds),systemImage:"timer")
                                    Spacer()
                                    Text("도착 \(record.reachedPointCount)개 지점")
                                    Image(systemName:"chevron.right").font(.caption)
                                }.font(.subheadline)
                            }.padding(20).background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:20))
                        }.buttonStyle(.plain)
                    }
                }.padding(20)
            }.navigationTitle("기록")
                .task {await library.refreshGuidanceRecords()}
                .refreshable {await library.refreshGuidanceRecords()}
        }
    }
}

private struct GuidanceRecordDetail: View {
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
                    metric("안내 시간",duration(record.activeSeconds))
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

private func duration(_ seconds: Double) -> String {
    let value=Int(seconds.rounded(.down))
    return value >= 3600 ? String(format:"%d:%02d:%02d",value/3600,(value/60)%60,value%60) : String(format:"%02d:%02d",value/60,value%60)
}
