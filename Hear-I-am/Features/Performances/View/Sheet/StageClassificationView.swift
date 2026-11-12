import SwiftUI
import HearIAmCore

/// The scan is already durable when this screen opens. Classification never gates the AR save.
struct StageClassificationView: View {
    @ObservedObject var library: StageLibrary
    let scanIDs: [UUID]
    let wasJustSaved: Bool
    let opensPerformanceOnCompletion: Bool
    /// Pushed inside the scan flow's navigation stack: no stack of its own, the system back button, and the
    /// flow decides where to go after saving.
    let embedded: Bool
    let onClassified: (UUID?) -> Void
    @State private var performanceID: UUID?
    @State private var venueID: UUID?
    @State private var stageName: String
    @State private var busy = false
    @State private var error: String?
    @State private var leaving = false
    @Environment(\.dismiss) private var dismiss

    init(library: StageLibrary, scanIDs: [UUID], initialPerformanceID: UUID? = nil,
         initialVenueID: UUID? = nil, wasJustSaved: Bool = false,
         opensPerformanceOnCompletion: Bool = false, embedded: Bool = false, onClassified: @escaping (UUID?) -> Void) {
        self.library = library; self.scanIDs = scanIDs; self.embedded = embedded
        self.wasJustSaved = wasJustSaved; self.opensPerformanceOnCompletion = opensPerformanceOnCompletion
        self.onClassified = onClassified
        let assignment = scanIDs.count == 1 ? library.catalog.assignments[scanIDs[0]] : nil
        let selectedPerformanceID = initialPerformanceID ?? assignment?.performanceID
        _performanceID = State(initialValue: selectedPerformanceID)
        _venueID = State(initialValue: initialVenueID ?? (selectedPerformanceID == assignment?.performanceID ? assignment?.venueID : nil))
        _stageName = State(initialValue: scanIDs.count == 1 ? library.records.first { $0.id == scanIDs[0] }?.name ?? "" : "")
    }
    private var scans: [ScanManifest] { library.records.filter { scanIDs.contains($0.id) } }
    /// Every stage belongs to a performance and a space (#181): there are no unfiled stages any more.
    private var invalid: Bool {
        scanIDs.isEmpty || scans.count != scanIDs.count || performanceID == nil || venueID == nil ||
        (scans.count == 1 && (stageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || stageName.count > 80))
    }
    var body: some View {
        if embedded { page } else { NavigationStack { page }.v3Screen() }
    }
    private var page: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    StageInfoTitle(text: wasJustSaved ? L("스캔한 무대의\n정보를 입력해주세요") : L("무대의 저장 위치를\n선택해주세요"))
                    if let scan = scans.first, scans.count == 1 { ScanSavedSummary(scan: scan).padding(.top, 28.6) }
                    StageInformationFields(library: library, stageName: $stageName,
                        performanceID: $performanceID, venueID: $venueID, showsName: scans.count == 1, afterScan: true)
                        .disabled(busy).padding(.top, scans.count == 1 ? 31 : 32.6)
                    if scans.count != scanIDs.count {
                        Text(L("저장한 무대를 불러오지 못했어요. 목록을 새로고침한 뒤 다시 시도해주세요.")).foregroundStyle(.red).padding(.top, 16)
                    }
                    if let error { Text(error).font(.callout).foregroundStyle(.red).padding(.top, 16) }
                }.padding(.horizontal, 16).padding(.top, StageInfoStyle.titleTop).padding(.bottom, 24)
            }.v3Screen().navigationTitle(L("무대 저장"))
                // Back leaves the page: inside the scan flow it goes back to the scan tab, as a sheet it closes it.
                .hearTopBar(L("무대 저장")) {
                    if wasJustSaved {
                        // A scan left here unsaved would have no performance (#181): ask, then delete it.
                        Button { leaving = true } label: { HearTopButtonLabel(systemImage: "chevron.left") }
                            .buttonStyle(.plain).disabled(busy).opacity(busy ? 0.45 : 1)
                            .accessibilityLabel(L("뒤로")).accessibilityIdentifier("top.back")
                    } else {
                        HearBackButton(enabled: !busy)
                    }
                } trailing: { EmptyView() }
                .holdsSwipeBack(wasJustSaved)
                .hearConfirm(L("저장하지 않고 나갈까요?"), isPresented: $leaving,
                             message: L("스캔한 무대와 사진이 지워져요."), confirm: L("나가기")) { discard() }
                .stageInfoBottomBar(height: 62) {
                    StageInfoButton(title: busy ? L("저장 중…") : L("저장하기"), primary: true, action: apply)
                        .disabled(busy || invalid)
                        .accessibilityIdentifier("classification.save")
                        .padding(.horizontal, 16)
                }
                .interactiveDismissDisabled(busy)
    }
    private func discard() {
        busy = true; error = nil
        Task {
            do {
                for id in scanIDs { try await library.deleteStage(id) }
                busy = false
                dismiss()
            } catch { self.error = error.localizedDescription; busy = false }
        }
    }
    private func apply() {
        guard !busy, !invalid else { return }
        busy = true; error = nil
        Task {
            do {
                if scans.count == 1, let scan = scans.first {
                    let name = stageName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if scan.name != name { try await library.renameStage(scan.id, to: name) }
                }
                try await library.assignScans(scanIDs, to: performanceID, venueID: venueID)
                busy = false
                onClassified(performanceID)
                if !embedded { dismiss() }
            } catch { self.error = error.localizedDescription; busy = false }
        }
    }
}

/// The stage information pages' look (Figma 971:22703 · 971:22741 · 971:22591 · 971:22532).
enum StageInfoStyle {
    static let canvas = Color(red: 17/255, green: 17/255, blue: 17/255)
    static let field = Color(red: 28/255, green: 28/255, blue: 30/255)
    static let placeholder = Color(red: 118/255, green: 118/255, blue: 118/255)
    static let filled = Color(red: 250/255, green: 250/255, blue: 250/255)
    static let secondary = Color(red: 235/255, green: 235/255, blue: 245/255).opacity(0.7)
    static let buttonText = Color(red: 38/255, green: 38/255, blue: 38/255)
    static let listRow = Color.white.opacity(0.05)
    static let green = Color(red: 46/255, green: 212/255, blue: 122/255)
    static let greenText = Color(red: 77/255, green: 219/255, blue: 148/255)
    /// The title's distance under the navigation bar (title top 154pt on the design's screen).
    static let titleTop: CGFloat = 24
}

extension View {
    /// The pages' bottom buttons, in their own layer: they stay at the bottom of the screen while the keyboard
    /// covers them, and only the scrolling content above makes room for the keyboard (so the field being typed
    /// in stays in view). The content can scroll under the glass buttons; `height` keeps its end clear of them.
    func stageInfoBottomBar<Bar: View>(height: CGFloat, @ViewBuilder _ bar: () -> Bar) -> some View {
        ZStack {
            safeAreaPadding(.bottom, height)
            VStack(spacing: 0) { Spacer(minLength: 0); bar() }
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }
}

/// 28pt semibold over two lines at the design's 1.4 line height.
struct StageInfoTitle: View {
    let text: String
    var body: some View {
        Text(text).font(HearFont.pretendard(.semibold, size: 28)).tracking(-0.84).lineSpacing(5.8)
            .foregroundStyle(.white).padding(.horizontal, 4).accessibilityAddTraits(.isHeader)
    }
}

/// The 50pt capsule at the bottom, in the system's Liquid Glass like the other buttons on these pages:
/// white-tinted glass for the main action, plain dark glass for the other (Figma 971:22735 · 971:22737).
struct StageInfoButton: View {
    let title: String
    let primary: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        Button(action: action) {
            Text(title).font(HearFont.pretendard(.semibold, size: 18))
                .foregroundStyle(primary ? StageInfoStyle.buttonText : .white)
                .frame(maxWidth: .infinity).frame(height: 50)
                .liquidGlass(Capsule(), tint: primary ? .white : nil, interactive: true)
                .contentShape(Capsule())
        }.buttonStyle(.plain).opacity(isEnabled ? 1 : 0.4)
    }
}

/// Shared by the before/after scan screens: the same folder selections survive the scan session.
struct StageInformationFields: View {
    @ObservedObject var library: StageLibrary
    @Binding var stageName: String
    @Binding var performanceID: UUID?
    @Binding var venueID: UUID?
    var showsName = true
    /// The post-scan page names the field 「장면 명」 and sets the chosen names in medium (971:22741).
    var afterScan = false
    @State private var choosingPerformance = false
    @State private var choosingVenue = false
    private var folder: PerformanceFolder? { library.performanceFolders.first { $0.id == performanceID } }
    private var venue: PerformanceVenueTag? { folder?.venues.first { $0.id == venueID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if showsName {
                section(afterScan ? L("장면 명") : L("무대(장면) 명")) {
                    TextField("", text: $stageName, prompt: Text(L("ex. 소말리아 해적선")).foregroundColor(StageInfoStyle.placeholder))
                        .font(HearFont.pretendard(.regular, size: 16)).foregroundStyle(StageInfoStyle.filled)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 16).frame(height: 48)
                        .background(StageInfoStyle.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel(afterScan ? L("장면 명") : L("무대(장면) 명"))
                        .accessibilityIdentifier("scan.sceneName")
                    if stageName.count > 80 { Text(L("장면 이름은 80자 이내로 입력해주세요.")).font(.caption).foregroundStyle(.red).padding(.horizontal, 4) }
                }
            }
            section(L("공연 이름")) {
                Button { choosingPerformance = true } label: {
                    selectionRow(folder?.name ?? L("공연 선택"), date: folder?.createdAt)
                }.buttonStyle(.plain).accessibilityIdentifier("classification.performance")
            }
            section(L("공연 및 연습 장소")) {
                Button { if folder == nil { choosingPerformance = true } else { choosingVenue = true } } label: {
                    selectionRow(venue?.name ?? L("장소 선택"), date: venue?.createdAt)
                }.buttonStyle(.plain).accessibilityIdentifier("classification.venue")
                if folder == nil {
                    Text(L("공연을 선택하면 장소를 지정할 수 있어요.")).font(HearFont.pretendard(.regular, size: 13))
                        .foregroundStyle(StageInfoStyle.secondary).padding(.horizontal, 4)
                }
            }
        }
        .navigationDestination(isPresented: $choosingPerformance) {
            PerformanceChoiceSheet(library: library, selection: performanceID) { id in
                if performanceID != id {
                    let venues = library.performanceFolders.first { $0.id == id }?.venues ?? []
                    venueID = venues.count == 1 ? venues[0].id : nil
                }
                performanceID = id
            }.suspendsVoiceWake()
        }
        .navigationDestination(isPresented: $choosingVenue) {
            if let performanceID {
                VenueChoiceSheet(library: library, performanceID: performanceID, selection: venueID) { venueID = $0 }.suspendsVoiceWake()
            }
        }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(HearFont.pretendard(.semibold, size: 20)).foregroundStyle(.white).padding(.horizontal, 4)
            content()
        }
    }
    private func selectionRow(_ name: String, date: Date?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(HearFont.pretendard(afterScan ? .medium : .semibold, size: 18))
                    .foregroundStyle(date == nil ? StageInfoStyle.placeholder : .white).lineLimit(1)
                if let date {
                    Text(PerformanceFolderRow.dateLabel(date)).font(HearFont.pretendard(.regular, size: 14)).foregroundStyle(StageInfoStyle.placeholder)
                }
            }
            Spacer(minLength: 12)
            Image(systemName: "chevron.right").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
        }.padding(.leading, 20).padding(.trailing, 22).frame(height: 70)
            .background(StageInfoStyle.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous)).contentShape(Rectangle())
    }
}

/// 「스캔 요약 / 분리형 타일」 (971:22748): two status rows and three counts.
private struct ScanSavedSummary: View {
    let scan: ScanManifest
    var body: some View {
        // 971:29917: the three counts first, then the two status rows.
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                count(L("지점"), scan.route?.points.count ?? 0)
                count(L("기물"), scan.route?.obstacles.count ?? 0)
                count(L("확인점"), scan.secondCheckpoint == nil ? 1 : 2)
            }
            status(L("안전구역"), value: scan.route == nil ? L("미지정") : L("지정완료"), green: scan.route != nil)
            status(L("스캔 구역 별 이미지"), value: scan.photos.isEmpty ? L("사진 없음") : L("저장완료"), green: false)
        }
    }
    private func status(_ title: String, value: String, green: Bool) -> some View {
        HStack {
            Text(title).font(HearFont.pretendard(.semibold, size: 15)).foregroundStyle(.white); Spacer()
            // One size for every chip (the longest, 「사진 없음」), so the two rows line up (11/07).
            Text(value).font(HearFont.pretendard(.semibold, size: 12)).lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: 70, height: 24)
                .foregroundStyle(green ? StageInfoStyle.greenText : StageInfoStyle.canvas)
                .background(green ? StageInfoStyle.green.opacity(0.15) : .white, in: Capsule())
        }.padding(.leading, 16).padding(.trailing, 12).frame(height: 44)
            .background(green ? StageInfoStyle.green.opacity(0.1) : StageInfoStyle.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    private func count(_ name: String, _ value: Int) -> some View {
        // Centred label over the number, with no tile behind it (971:29927).
        VStack(spacing: 4) {
            Text(name).font(HearFont.pretendard(.regular, size: 13)).foregroundStyle(StageInfoStyle.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)").font(HearFont.pretendard(.semibold, size: 25)).foregroundStyle(.white)
                Text(L("개")).font(HearFont.pretendard(.regular, size: 12)).foregroundStyle(StageInfoStyle.secondary)
            }
        }.frame(maxWidth: .infinity).frame(height: 72)
            .accessibilityElement(children: .combine)
    }
}

/// One folder or space in the choice pages (971:22591 · 971:22532): name, date, scan count badge and chevron.
private struct StageChoiceRow: View {
    let name: String
    let date: Date
    let count: Int
    var weight: HearFont.Pretendard = .medium
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(HearFont.pretendard(weight, size: 18)).foregroundStyle(.white).lineLimit(1)
                Text(PerformanceFolderRow.dateLabel(date)).font(HearFont.pretendard(.regular, size: 14)).foregroundStyle(StageInfoStyle.placeholder)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text("\(count)").font(HearFont.pretendard(.regular, size: 13)).foregroundStyle(.white).monospacedDigit()
                .frame(minWidth: 22, minHeight: 22).background(.white.opacity(0.1), in: Capsule())
                .accessibilityLabel(L("스캔 파일 %@개", count))
            Image(systemName: "chevron.right").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).accessibilityHidden(true)
        }.padding(.leading, 20).padding(.trailing, 22).frame(height: 70)
            .background(StageInfoStyle.listRow, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// The capsule search field at the top of the choice pages.
private struct StageChoiceSearchField: View {
    @Binding var text: String
    let prompt: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(StageInfoStyle.placeholder).frame(width: 24, height: 24)
            TextField("", text: $text, prompt: Text(prompt).foregroundColor(StageInfoStyle.placeholder))
                .font(HearFont.pretendard(.regular, size: 16)).foregroundStyle(.white)
                .autocorrectionDisabled().textInputAutocapitalization(.never).submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(StageInfoStyle.placeholder) }
                    .buttonStyle(.plain).accessibilityLabel(L("검색 지우기"))
            }
        }.padding(.horizontal, 16).frame(height: 48)
            .background(StageInfoStyle.listRow, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }
}

/// Pushed from the stage information page (971:22591).
struct PerformanceChoiceSheet: View {
    @ObservedObject var library: StageLibrary
    let selection: UUID?
    let onSelect: (UUID?) -> Void
    @State private var query = ""
    @State private var creating = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                StageChoiceSearchField(text: $query, prompt: L("공연 이름 검색"))
                VStack(spacing: 6) {
                    ForEach(library.performanceFolders.filter { query.isEmpty || $0.name.localizedStandardContains(query) }) { folder in
                        Button { onSelect(folder.id); dismiss() } label: {
                            StageChoiceRow(name: folder.name, date: folder.createdAt, count: library.scans(in: folder.id).count)
                        }.buttonStyle(.plain).accessibilityAddTraits(selection == folder.id ? .isSelected : [])
                    }
                }
            }.padding(.horizontal, 16).padding(.top, StageInfoStyle.titleTop).padding(.bottom, 24)
        }.v3Screen().navigationTitle(L("공연 이름"))
            .hearTopBar(L("공연 이름")) { HearBackButton() } trailing: {
                Button { creating = true } label: { HearTopButtonLabel(systemImage: "plus", prominent: true) }
                    .buttonStyle(.plain).accessibilityLabel(L("새 공연"))
            }
            .sheet(isPresented: $creating) { PerformanceEditorSheet(library: library) { id in onSelect(id); dismiss() } }
    }
}

/// Pushed from the stage information page (971:22532).
struct VenueChoiceSheet: View {
    @ObservedObject var library: StageLibrary
    let performanceID: UUID
    let selection: UUID?
    let onSelect: (UUID?) -> Void
    @State private var query = ""
    @State private var creating = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    private var folder: PerformanceFolder? { library.performanceFolders.first { $0.id == performanceID } }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                StageChoiceSearchField(text: $query, prompt: L("공연 및 연습 공간 검색"))
                VStack(spacing: 6) {
                    ForEach((folder?.venues ?? []).filter { query.isEmpty || $0.name.localizedStandardContains(query) }) { venue in
                        Button { onSelect(venue.id); dismiss() } label: {
                            StageChoiceRow(name: venue.name, date: venue.createdAt,
                                count: library.scans(in: performanceID, venueID: venue.id, includeAllVenues: false).count, weight: .semibold)
                        }.buttonStyle(.plain).accessibilityAddTraits(selection == venue.id ? .isSelected : [])
                    }
                }
            }.padding(.horizontal, 16).padding(.top, StageInfoStyle.titleTop).padding(.bottom, 24)
        }.v3Screen().navigationTitle(L("공연 및 연습 공간"))
            .hearTopBar(L("공연 및 연습 공간")) { HearBackButton() } trailing: {
                Button { creating = true } label: { HearTopButtonLabel(systemImage: "plus", prominent: true) }
                    .buttonStyle(.plain).accessibilityLabel(L("새 공간"))
            }
            .sheet(isPresented: $creating) {
                PerformanceSpaceSearchSheet { name in
                    creating = false
                    saveVenue(named: name)
                }.suspendsVoiceWake()
            }
            .alert(L("공간을 추가하지 못했어요"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(L("확인"), role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
    }
    private func saveVenue(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // The same name as the store compares them: 「CKL Stage」 is 「ckl  stage」. Matching exactly let such a name
        // through to a save that refused it, with nothing on screen (#179).
        let key = PlaceSearch.normalized(trimmed)
        if let existing = folder?.venues.first(where: { PlaceSearch.normalized($0.name) == key }) {
            onSelect(existing.id)
            dismiss()
            return
        }
        Task {
            do {
                let created = try await library.createVenue(name: trimmed, in: performanceID)
                onSelect(created.id)
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct VenueEditorSheet: View {
    @ObservedObject var library: StageLibrary
    let performanceID: UUID
    let venue: PerformanceVenueTag?
    let onSaved: (UUID) -> Void
    @State private var name: String
    @State private var busy = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(library: StageLibrary, performanceID: UUID, venue: PerformanceVenueTag? = nil, onSaved: @escaping (UUID) -> Void) {
        self.library = library; self.performanceID = performanceID; self.venue = venue; self.onSaved = onSaved
        _name = State(initialValue: venue?.name ?? "")
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L("공연 및 연습 공간 이름")).font(.title3.bold())
                    TextField(L("예: 효자 아트홀"), text: $name).autocorrectionDisabled().padding(16)
                        .background(HearV3.surface, in: RoundedRectangle(cornerRadius: 14))
                    if let error { Text(error).foregroundStyle(.red).font(.callout) }
                }.padding(20).padding(.top, 24)
            }.v3Screen().navigationTitle(venue == nil ? L("새 공간") : L("공간 이름 수정")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L("닫기"), systemImage: "chevron.left") { dismiss() }.labelStyle(.iconOnly).disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button(L("저장"), systemImage: "checkmark", action: save).labelStyle(.iconOnly).buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black).disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80) }
                }.interactiveDismissDisabled(busy)
        }.v3Screen()
    }
    private func save() {
        guard !busy else { return }; busy = true; error = nil
        Task {
            do {
                let id: UUID
                if let venue { try await library.renameVenue(venue.id, in: performanceID, to: name); id = venue.id }
                else { id = try await library.createVenue(name: name, in: performanceID).id }
                onSaved(id); dismiss()
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
