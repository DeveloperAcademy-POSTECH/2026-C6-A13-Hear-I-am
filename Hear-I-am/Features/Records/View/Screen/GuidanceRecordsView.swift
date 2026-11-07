import SwiftUI
import HearIAmCore

/// Completed runs use the same explicit surfaces and spacing as the V3 performance library.
struct GuidanceRecordsView: View {
    @ObservedObject var library: StageLibrary
    @Environment(\.hearChangeRole) private var changeRole
    @State private var isRefreshing=false
    @State private var hasLoaded=false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    introduction
                    if let error=library.recordError {errorCard(error)}
                    if library.guidanceRecords.isEmpty {
                        if !hasLoaded || isRefreshing {
                            ProgressView("기록을 불러오는 중이에요")
                                .frame(maxWidth:.infinity,minHeight:220)
                                .accessibilityIdentifier("records.loading")
                        } else if library.recordError == nil {
                            ContentUnavailableView("아직 저장된 기록이 없어요",systemImage:"clock",description:Text("이동 안내를 완료하면\n이곳에서 다시 살펴볼 수 있어요."))
                                .frame(maxWidth:.infinity,minHeight:220)
                                .v3Card(inset:16)
                                .accessibilityIdentifier("records.empty")
                        }
                    } else {
                        records
                    }
                }.padding(20)
            }.v3Screen()
                .navigationTitle("기록")
                // Home on the left as on the other two tabs; refresh and settings on the right (11/07).
                .hearTopBar("기록") {
                    Button {changeRole?()} label: {HearTopButtonLabel(systemImage:"house")}
                        .buttonStyle(.plain).accessibilityLabel("역할 선택으로 돌아가기")
                } trailing: {
                    Button {Task {await reloadRecords()}} label: {HearTopButtonLabel(systemImage:"arrow.clockwise")}
                        .buttonStyle(.plain).disabled(isRefreshing)
                        .accessibilityLabel("기록 새로고침")
                        .accessibilityIdentifier("records.refresh")
                    NavigationLink {HomeSettingsView()} label: {HearTopButtonLabel(systemImage:"gearshape")}
                        .buttonStyle(.plain).accessibilityLabel("설정")
                        .accessibilityIdentifier("records.settings")
                }
                .task {await reloadRecords()}
                .refreshable {await reloadRecords()}
        }.v3Screen()
    }

    private var introduction: some View {
        VStack(alignment:.leading,spacing:8) {
            Text("무대 위의 발자취").font(.title.bold())
                .foregroundStyle(HearV3.text).accessibilityAddTraits(.isHeader)
            Text("연습과 공연에서 걸어온 길을 살펴보세요.")
                .font(.subheadline).foregroundStyle(HearV3.secondary)
                .fixedSize(horizontal:false,vertical:true)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }

    private var records: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("최근 기록 · \(library.guidanceRecords.count)개")
                .font(.subheadline.weight(.semibold)).foregroundStyle(HearV3.secondary)
                .accessibilityAddTraits(.isHeader)
            LazyVStack(spacing:12) {
                ForEach(library.guidanceRecords) {record in
                    NavigationLink {GuidanceRecordDetail(record:record)} label: {recordCard(record)}
                        .buttonStyle(.plain)
                        .accessibilityElement(children:.combine)
                        .accessibilityHint("완료한 안내의 상세 정보와 이동 경로를 확인해요.")
                        .accessibilityIdentifier("records.\(record.id)")
                }
            }
            Text("마지막 지점에 도착한 뒤 종료한 안내만 기록돼요.")
                .font(.footnote).foregroundStyle(HearV3.secondary)
                .fixedSize(horizontal:false,vertical:true)
        }
    }

    private func recordCard(_ record: GuidanceRecord) -> some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.top,spacing:12) {
                VStack(alignment:.leading,spacing:7) {
                    Text(record.stageName).font(.headline).foregroundStyle(HearV3.text)
                        .fixedSize(horizontal:false,vertical:true)
                    Text(record.completedAt.formatted(.dateTime.locale(Locale(identifier:"ko_KR")).year().month().day().hour().minute()))
                        .font(.subheadline).foregroundStyle(HearV3.secondary)
                        .fixedSize(horizontal:false,vertical:true)
                }.frame(maxWidth:.infinity,alignment:.leading)
                Image(systemName:"chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(HearV3.secondary).padding(.top,4).accessibilityHidden(true)
            }
            // Keep the badge from squeezing the duration on narrow screens or at larger text sizes.
            ViewThatFits(in:.horizontal) {
                HStack(spacing:12) {
                    summary(record).fixedSize(horizontal:true,vertical:false)
                    Spacer(minLength:0)
                    completedBadge.fixedSize()
                }
                VStack(alignment:.leading,spacing:10) {
                    summary(record)
                    completedBadge
                }
            }
        }.v3Card(inset:20).contentShape(RoundedRectangle(cornerRadius:24,style:.continuous))
    }

    private func summary(_ record: GuidanceRecord) -> some View {
        Text("안내 \(record.activeDurationText) · \(record.reachedPointCount)개 지점 도착")
            .font(.footnote).foregroundStyle(HearV3.secondary)
            .fixedSize(horizontal:false,vertical:true)
    }

    private var completedBadge: some View {
        Text("완료").font(.caption.weight(.medium)).foregroundStyle(HearV3.accent)
            .padding(.horizontal,10).padding(.vertical,5)
            .background(HearV3.accent.opacity(0.15),in:Capsule())
    }

    private func errorCard(_ error: String) -> some View {
        VStack(alignment:.leading,spacing:12) {
            Label("기록을 불러오지 못했어요",systemImage:"exclamationmark.triangle")
                .font(.headline).foregroundStyle(HearV3.text)
            Text(error).font(.subheadline).foregroundStyle(HearV3.secondary)
                .fixedSize(horizontal:false,vertical:true)
            Button("다시 불러오기") {Task {await reloadRecords()}}
                .buttonStyle(.bordered).disabled(isRefreshing)
                .accessibilityIdentifier("records.retry")
        }.v3Card(inset:20)
    }

    @MainActor private func reloadRecords() async {
        guard !isRefreshing else {return}
        isRefreshing=true
        await library.refreshGuidanceRecords()
        isRefreshing=false
        hasLoaded=true
    }
}
