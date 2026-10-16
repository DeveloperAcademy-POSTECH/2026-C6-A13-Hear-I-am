import SwiftUI
import HearIAmCore

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
                                    Label(record.activeDurationText,systemImage:"timer")
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
