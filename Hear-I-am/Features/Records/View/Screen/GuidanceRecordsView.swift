import SwiftUI
import HearIAmCore

/// Figma 공연/연습 기록 (971:30918 · 971:31032): home and the sort-and-filter menu on top, the title, the search
/// field and one row per completed run. Sorting and filtering work as on the performance list (971:31052).
struct GuidanceRecordsView: View {
    @ObservedObject var library: StageLibrary
    @Environment(\.hearChangeRole) private var changeRole
    @State private var isRefreshing=false
    @State private var hasLoaded=false
    @State private var query=""
    @State private var sort=PerformanceSort.newest
    @State private var period=PerformancePeriod.all
    /// Venue names to keep; empty keeps every record.
    @State private var venueFilter: Set<String> = []
    @State private var choosingVenues=false
    @State private var opened: UUID?
    @State private var deleting: GuidanceRecord?
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    VStack(alignment:.leading,spacing:12) {
                        Text("공연/연습 기록").font(HearFont.pretendard(.semibold,size:28)).foregroundStyle(.white)
                            .padding(.horizontal,5).accessibilityAddTraits(.isHeader)
                        PerformanceSearchField(text:$query,prompt:"공연 이름 또는 장소 검색")
                    }
                    if let error=library.recordError {errorCard(error)}
                    if library.guidanceRecords.isEmpty && (!hasLoaded || isRefreshing) {
                        ProgressView("기록을 불러오는 중이에요").frame(maxWidth:.infinity,minHeight:260)
                            .accessibilityIdentifier("records.loading")
                    } else if records.isEmpty {
                        if library.recordError == nil {empty}
                    } else {
                        LazyVStack(spacing:4) {
                            ForEach(records) {record in
                                // Slides left to delete, as the performance list does.
                                HearSwipeDeleteRow(onOpen:{opened=record.id},onDelete:{deleting=record}) {
                                    GuidanceRecordRow(title:title(record),date:record.completedAt,venue:venue(record),
                                                      duration:record.activeSeconds,points:record.reachedPointCount)
                                }.accessibilityIdentifier("records.\(record.id)")
                            }
                        }
                    }
                }.padding(.horizontal,16).padding(.top,24).padding(.bottom,24)
            }.v3Screen()
                .hearTopBar(nil) {
                    Button {changeRole?()} label: {HearTopButtonLabel(systemImage:"house")}
                        .buttonStyle(.plain).accessibilityLabel("역할 선택으로 돌아가기")
                } trailing: {
                    HearSortFilterMenu(sort:$sort,period:$period,venueCount:venueFilter.count) {choosingVenues=true}
                }
                .task {await reloadRecords()}
                .refreshable {await reloadRecords()}
                .navigationDestination(item:$opened) {id in
                    if let record=library.guidanceRecords.first(where:{$0.id == id}) {GuidanceRecordDetail(record:record,library:library)}
                }
                .hearConfirm("이 기록을 삭제할까요?",isPresented:Binding(get:{deleting != nil},set:{if !$0 {deleting=nil}}),
                             message:"\(deleting.map(GuidanceRecordDetail.dateLabel) ?? "") 기록이 삭제돼요.\n삭제한 기록은 복구할 수 없어요.") {
                    guard let record=deleting else {return}
                    Task {
                        do {try await library.deleteGuidanceRecord(record.id)}
                        catch {deleteError=error.localizedDescription}
                    }
                }
                .alert("삭제하지 못했어요",isPresented:Binding(get:{deleteError != nil},set:{if !$0 {deleteError=nil}})) {
                    Button("확인",role:.cancel) {deleteError=nil}
                } message: {Text(deleteError ?? "")}
                .sheet(isPresented:$choosingVenues) {
                    PerformanceVenueFilterSheet(names:venueNames,selection:venueFilter) {venueFilter=$0}
                }
        }.v3Screen()
    }

    /// The performance the run's stage belonged to when it finished; the stage's own name when it was not filed under
    /// one. Records saved before #179 have no names of their own and still look them up.
    private func title(_ record: GuidanceRecord) -> String {
        if let name=record.performanceName {return name.isEmpty ? record.stageName : name}
        return library.catalog.folder(for:record.stageID)?.name ?? record.stageName
    }
    private func venue(_ record: GuidanceRecord) -> String? {
        if let name=record.venueName {return name.isEmpty ? nil : name}
        return library.catalog.venue(for:record.stageID)?.name
    }
    private var filtering: Bool {!query.isEmpty || !venueFilter.isEmpty || period != .all}
    private var records: [GuidanceRecord] {
        let search=query.trimmingCharacters(in:.whitespacesAndNewlines)
        let since=period.days.map {Date().addingTimeInterval(-Double($0)*86_400)}
        let matches=library.guidanceRecords.filter {record in
            let venue=venue(record)
            return (search.isEmpty || title(record).localizedStandardContains(search) || record.stageName.localizedStandardContains(search)
                    || (venue?.localizedStandardContains(search) ?? false))
                && (venueFilter.isEmpty || venue.map(venueFilter.contains) == true)
                && (since.map {record.completedAt >= $0} ?? true)
        }
        switch sort {
        case .newest: return matches.sorted {$0.completedAt > $1.completedAt}
        case .oldest: return matches.sorted {$0.completedAt < $1.completedAt}
        case .name: return matches.sorted {title($0).localizedStandardCompare(title($1)) == .orderedAscending}
        }
    }
    /// Every venue of every performance and of the runs, once each.
    private var venueNames: [String] {
        let names=library.performanceFolders.flatMap(\.venues).map(\.name)+library.guidanceRecords.compactMap(venue)
        return Array(Set(names)).sorted {$0.localizedStandardCompare($1) == .orderedAscending}
    }
    /// 971:31032: the tape symbol over 「아직 저장된 기록이 없어요」, in the middle of what is left of the screen.
    private var empty: some View {
        VStack(spacing:20) {
            Image(systemName:"recordingtape").font(.system(size:40,weight:.medium)).accessibilityHidden(true)
            Text(filtering ? "찾는 기록이 없어요" : "아직 저장된 기록이 없어요").font(HearFont.pretendard(.semibold,size:22))
        }.foregroundStyle(PerformanceSearchField.grey).multilineTextAlignment(.center)
            .frame(maxWidth:.infinity,minHeight:420).accessibilityIdentifier("records.empty")
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
        // The performance and venue names come from the catalog, which another tab may not have loaded yet.
        if library.catalog.performances.isEmpty {await library.refresh()}
        await library.refreshGuidanceRecords()
        isRefreshing=false
        hasLoaded=true
    }
}

/// 971:30933: the performance and date, then where and how long, with the arrived points and a chevron.
struct GuidanceRecordRow: View {
    let title: String
    let date: Date
    let venue: String?
    let duration: Double
    let points: Int
    private static let grey=PerformanceSearchField.grey
    var body: some View {
        HStack(spacing:12) {
            VStack(alignment:.leading,spacing:12) {
                HStack(alignment:.firstTextBaseline,spacing:8) {
                    Text(title).font(HearFont.pretendard(.medium,size:18)).foregroundStyle(.white).lineLimit(1)
                    Text(PerformanceFolderRow.dateLabel(date)).font(HearFont.pretendard(.regular,size:14)).foregroundStyle(Self.grey)
                }
                VStack(alignment:.leading,spacing:6) {
                    detail("pin",venue ?? "공간 미지정")
                    detail("clock",Self.durationLabel(duration))
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
            HStack(spacing:10) {
                Text("\(points)").font(HearFont.pretendard(.regular,size:13)).foregroundStyle(.white).monospacedDigit()
                    .frame(minWidth:22,minHeight:22).background(.white.opacity(0.1),in:Capsule())
                Image(systemName:"chevron.right").font(.system(size:17,weight:.semibold)).foregroundStyle(.white)
            }.accessibilityHidden(true)
        }.padding(.leading,22).padding(.trailing,22).frame(minHeight:111)
            .background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:16,style:.continuous))
            .contentShape(RoundedRectangle(cornerRadius:16,style:.continuous))
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("\(title), \(PerformanceFolderRow.dateLabel(date)), \(venue ?? "공간 미지정"), \(Self.durationLabel(duration)), 지점 \(points)곳 도착")
            .accessibilityAddTraits(.isButton)
    }
    private func detail(_ symbol: String,_ text: String) -> some View {
        HStack(spacing:8) {
            Image(systemName:symbol).font(.system(size:12)).foregroundStyle(Self.grey).frame(width:14)
            Text(text).font(HearFont.pretendard(.regular,size:14)).tracking(-0.42).foregroundStyle(Color(white:0.98)).lineLimit(1)
        }
    }
    /// 「1분 37초」; seconds alone under a minute, hours and minutes from an hour.
    static func durationLabel(_ seconds: Double) -> String {
        let value=Int(max(0,seconds).rounded(.down))
        if value>=3600 {return "\(value/3600)시간 \((value/60)%60)분"}
        if value>=60 {return "\(value/60)분 \(value%60)초"}
        return "\(value)초"
    }
}
