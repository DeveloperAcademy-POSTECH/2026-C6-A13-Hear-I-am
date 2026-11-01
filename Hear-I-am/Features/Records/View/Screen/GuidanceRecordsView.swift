import SwiftUI
import HearIAmCore

/// The existing completed-run collection, presented in the V3 helper shell.
struct GuidanceRecordsView: View {
    @ObservedObject var library:StageLibrary
    @Environment(\.hearChangeRole) private var changeRole
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment:.leading,spacing:8) {
                        Text("무대 위의 발자취").font(.title.bold())
                        Text("연습과 공연에서 걸어온 길을 살펴보세요.").font(.subheadline).foregroundStyle(HearV3.secondary)
                    }.padding(.vertical,12).listRowSeparator(.hidden)
                }
                if let error=library.recordError {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("다시 불러오기") {Task {await library.refreshGuidanceRecords()}}
                    }
                }
                if library.guidanceRecords.isEmpty && library.recordError == nil {
                    ContentUnavailableView("아직 저장된 기록이 없어요",systemImage:"clock",description:Text("이동 안내를 완료하면\n이곳에서 다시 살펴볼 수 있어요."))
                        .listRowSeparator(.hidden)
                }
                Section {
                    ForEach(library.guidanceRecords) {record in
                        NavigationLink {GuidanceRecordDetail(record:record)} label: {recordRow(record)}
                            .accessibilityIdentifier("records.\(record.id)")
                    }
                } header: {
                    if !library.guidanceRecords.isEmpty {Text("최근 기록 · \(library.guidanceRecords.count)개")}
                } footer: {
                    if !library.guidanceRecords.isEmpty {Text("마지막 지점에 도착한 뒤 종료한 안내만 기록돼요.")}
                }
            }.listStyle(.plain).scrollContentBackground(.hidden).background(HearV3.canvas)
                .navigationTitle("기록").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.topBarTrailing) {
                        NavigationLink {HomeSettingsView(role:.helper,changeRole:changeRole)} label: {Image(systemName:"gearshape")}
                            .accessibilityLabel("설정")
                    }
                }
                .task {await library.refreshGuidanceRecords()}
                .refreshable {await library.refreshGuidanceRecords()}
                .v3Screen()
        }
    }
    private func recordRow(_ record:GuidanceRecord)->some View {
        VStack(alignment:.leading,spacing:9) {
            Text(record.stageName).font(.headline)
            Text(record.completedAt.formatted(.dateTime.locale(Locale(identifier:"ko_KR")).month().day().hour().minute()))
                .font(.subheadline).foregroundStyle(HearV3.secondary)
            HStack {
                Text("안내 \(record.activeDurationText) · \(record.reachedPointCount)개 지점 도착")
                    .font(.caption).foregroundStyle(HearV3.secondary)
                Spacer(minLength:8)
                Text("완료").font(.caption.weight(.medium)).foregroundStyle(HearV3.accent)
                    .padding(.horizontal,8).padding(.vertical,4).background(HearV3.accent.opacity(0.15),in:Capsule())
            }
        }.padding(.vertical,12)
    }
}
