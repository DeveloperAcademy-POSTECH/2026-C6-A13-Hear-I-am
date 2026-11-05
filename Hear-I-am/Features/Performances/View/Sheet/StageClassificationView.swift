import SwiftUI
import HearIAmCore

/// The scan is already durable when this screen opens. Classification never gates the AR save.
struct StageClassificationView: View {
    @ObservedObject var library: StageLibrary
    let scanIDs: [UUID]
    let wasJustSaved: Bool
    let opensPerformanceOnCompletion: Bool
    let onClassified: (UUID?) -> Void
    @State private var performanceID: UUID?
    @State private var venueID: UUID?
    @State private var stageName: String
    @State private var busy = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(library: StageLibrary, scanIDs: [UUID], initialPerformanceID: UUID? = nil,
         initialVenueID: UUID? = nil, wasJustSaved: Bool = false,
         opensPerformanceOnCompletion: Bool = false, onClassified: @escaping (UUID?) -> Void) {
        self.library = library; self.scanIDs = scanIDs
        self.wasJustSaved = wasJustSaved; self.opensPerformanceOnCompletion = opensPerformanceOnCompletion
        self.onClassified = onClassified
        let assignment = scanIDs.count == 1 ? library.catalog.assignments[scanIDs[0]] : nil
        let selectedPerformanceID = initialPerformanceID ?? assignment?.performanceID
        _performanceID = State(initialValue: selectedPerformanceID)
        _venueID = State(initialValue: initialVenueID ?? (selectedPerformanceID == assignment?.performanceID ? assignment?.venueID : nil))
        _stageName = State(initialValue: scanIDs.count == 1 ? library.records.first { $0.id == scanIDs[0] }?.name ?? "" : "")
    }
    private var scans: [ScanManifest] { library.records.filter { scanIDs.contains($0.id) } }
    private var invalid: Bool {
        scanIDs.isEmpty || scans.count != scanIDs.count ||
        (scans.count == 1 && (stageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || stageName.count > 80))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(wasJustSaved ? "스캔한 무대의\n정보를 입력해주세요" : "무대의 저장 위치를\n선택해주세요")
                        .font(.title.bold()).lineSpacing(5).padding(.horizontal, 4)
                    if let scan = scans.first, scans.count == 1 { ScanSavedSummary(scan: scan) }
                    StageInformationFields(library: library, stageName: $stageName,
                        performanceID: $performanceID, venueID: $venueID, showsName: scans.count == 1).disabled(busy)
                    if scans.count != scanIDs.count {
                        Text("저장한 무대를 불러오지 못했어요. 목록을 새로고침한 뒤 다시 시도해주세요.").foregroundStyle(.red)
                    }
                    if let error { Text(error).font(.callout).foregroundStyle(.red) }
                }.padding(.horizontal, 16).padding(.top, 28).padding(.bottom, 24)
            }.v3Screen().navigationTitle("무대 저장").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기", systemImage: "chevron.left") { dismiss() }.labelStyle(.iconOnly).disabled(busy)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu { Button("저장 위치 초기화") { performanceID = nil; venueID = nil } } label: { Image(systemName: "ellipsis") }.disabled(busy)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Button(busy ? "저장 중…" : "저장하기", action: apply)
                        .buttonStyle(V3PrimaryButtonStyle()).disabled(busy || invalid)
                        .accessibilityIdentifier("classification.save")
                        .padding(.horizontal, 16).padding(.vertical, 12).background(HearV3.canvas)
                }
                .interactiveDismissDisabled(busy)
        }.v3Screen()
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
                dismiss()
            } catch { self.error = error.localizedDescription; busy = false }
        }
    }
}

/// Shared by the before/after scan screens: the same folder selections survive the scan session.
struct StageInformationFields: View {
    @ObservedObject var library: StageLibrary
    @Binding var stageName: String
    @Binding var performanceID: UUID?
    @Binding var venueID: UUID?
    var showsName = true
    @State private var choosingPerformance = false
    @State private var choosingVenue = false
    private var folder: PerformanceFolder? { library.performanceFolders.first { $0.id == performanceID } }
    private var venue: PerformanceVenueTag? { folder?.venues.first { $0.id == venueID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if showsName {
                VStack(alignment: .leading, spacing: 12) {
                    Text("무대(장면) 명").font(.title3.bold()).padding(.horizontal, 4)
                    TextField("예: 초원을 뛰어노는 장면", text: $stageName).autocorrectionDisabled()
                        .padding(.horizontal, 16).frame(minHeight: 48)
                        .background(HearV3.surface, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("scan.sceneName")
                    if stageName.count > 80 { Text("장면 이름은 80자 이내로 입력해주세요.").font(.caption).foregroundStyle(.red) }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("공연 이름").font(.title3.bold()).padding(.horizontal, 4)
                Button { choosingPerformance = true } label: {
                    selectionRow(folder?.name ?? "공연 선택", date: folder?.createdAt)
                }.buttonStyle(.plain).accessibilityIdentifier("classification.performance")
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("공연 및 연습 장소").font(.title3.bold()).padding(.horizontal, 4)
                Button { if folder == nil { choosingPerformance = true } else { choosingVenue = true } } label: {
                    selectionRow(venue?.name ?? "장소 선택", date: venue?.createdAt)
                }.buttonStyle(.plain).accessibilityIdentifier("classification.venue")
                if folder == nil { Text("공연을 선택하면 장소를 지정할 수 있어요.").font(.caption).foregroundStyle(HearV3.secondary) }
            }
        }
        .sheet(isPresented: $choosingPerformance) {
            PerformanceChoiceSheet(library: library, selection: performanceID) { id in
                if performanceID != id { venueID = nil }; performanceID = id
            }.suspendsVoiceWake()
        }
        .sheet(isPresented: $choosingVenue) {
            if let performanceID {
                VenueChoiceSheet(library: library, performanceID: performanceID, selection: venueID) { venueID = $0 }.suspendsVoiceWake()
            }
        }
    }
    private func selectionRow(_ name: String, date: Date?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(name).font(.headline).foregroundStyle(date == nil ? HearV3.secondary : HearV3.text)
                if let date { Text(PerformanceFolderRow.dateLabel(date)).font(.footnote).foregroundStyle(HearV3.secondary) }
            }
            Spacer(); Image(systemName: "chevron.right").font(.body.weight(.semibold))
        }.padding(.horizontal, 16).padding(.vertical, 14).frame(minHeight: 70)
            .background(HearV3.surface, in: RoundedRectangle(cornerRadius: 18)).contentShape(Rectangle())
    }
}

private struct ScanSavedSummary: View {
    let scan: ScanManifest
    var body: some View {
        VStack(spacing: 8) {
            status("안전구역", value: scan.route == nil ? "미지정" : "지정완료", green: scan.route != nil)
            status("스캔 구역 별 이미지", value: scan.photos.isEmpty ? "사진 없음" : "저장완료", green: false)
            HStack(spacing: 8) {
                count("지점", scan.route?.points.count ?? 0)
                count("기물", scan.route?.obstacles.count ?? 0)
                count("확인점", scan.secondCheckpoint == nil ? 1 : 2)
            }.padding(.top, 8)
        }
    }
    private func status(_ title: String, value: String, green: Bool) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold)); Spacer()
            Text(value).font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundStyle(green ? HearV3.accent : HearV3.canvas)
                .background(green ? HearV3.accent.opacity(0.15) : .white, in: Capsule())
        }.padding(.horizontal, 16).frame(minHeight: 44)
            .background(green ? HearV3.accent.opacity(0.1) : HearV3.surface, in: RoundedRectangle(cornerRadius: 16))
    }
    private func count(_ name: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name).font(.footnote).foregroundStyle(HearV3.secondary)
            (Text("\(value)").font(.title2.weight(.semibold)) + Text(" 개").font(.caption).foregroundColor(HearV3.secondary))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(HearV3.surface, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct PerformanceChoiceSheet: View {
    @ObservedObject var library: StageLibrary
    let selection: UUID?
    let onSelect: (UUID?) -> Void
    @State private var query = ""
    @State private var creating = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    PerformanceSearchField(text: $query, prompt: "공연 이름 검색").padding(.bottom, 10)
                    ForEach(library.performanceFolders.filter { query.isEmpty || $0.name.localizedStandardContains(query) }) { folder in
                        Button { onSelect(folder.id); dismiss() } label: {
                            PerformanceFolderRow(name: folder.name, date: folder.createdAt, count: library.scans(in: folder.id).count)
                        }.buttonStyle(.plain).accessibilityAddTraits(selection == folder.id ? .isSelected : [])
                    }
                    Button("공연을 지정하지 않기") { onSelect(nil); dismiss() }.frame(minHeight: 44).padding(.top, 12)
                }.padding(16).padding(.top, 16)
            }.v3Screen().navigationTitle("공연 이름").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("닫기", systemImage: "chevron.left") { dismiss() }.labelStyle(.iconOnly) }
                    ToolbarItem(placement: .primaryAction) { Button("새 공연", systemImage: "plus") { creating = true }.labelStyle(.iconOnly).buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black) }
                }
                .sheet(isPresented: $creating) { PerformanceEditorSheet(library: library) { id in onSelect(id); dismiss() } }
        }.v3Screen()
    }
}

struct VenueChoiceSheet: View {
    @ObservedObject var library: StageLibrary
    let performanceID: UUID
    let selection: UUID?
    let onSelect: (UUID?) -> Void
    @State private var query = ""
    @State private var creating = false
    @Environment(\.dismiss) private var dismiss
    private var folder: PerformanceFolder? { library.performanceFolders.first { $0.id == performanceID } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    PerformanceSearchField(text: $query, prompt: "공연 및 연습 공간 검색").padding(.bottom, 10)
                    ForEach((folder?.venues ?? []).filter { query.isEmpty || $0.name.localizedStandardContains(query) }) { venue in
                        Button { onSelect(venue.id); dismiss() } label: {
                            PerformanceFolderRow(name: venue.name, date: venue.createdAt,
                                count: library.scans(in: performanceID, venueID: venue.id, includeAllVenues: false).count)
                        }.buttonStyle(.plain).accessibilityAddTraits(selection == venue.id ? .isSelected : [])
                    }
                    Button("장소를 지정하지 않기") { onSelect(nil); dismiss() }.frame(minHeight: 44).padding(.top, 12)
                }.padding(16).padding(.top, 16)
            }.v3Screen().navigationTitle("공연 및 연습 공간").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("닫기", systemImage: "chevron.left") { dismiss() }.labelStyle(.iconOnly) }
                    ToolbarItem(placement: .primaryAction) { Button("새 공간", systemImage: "plus") { creating = true }.labelStyle(.iconOnly).buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black) }
                }
                .sheet(isPresented: $creating) { VenueEditorSheet(library: library, performanceID: performanceID) { id in onSelect(id); dismiss() } }
        }.v3Screen()
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
                    Text("공연 및 연습 공간 이름").font(.title3.bold())
                    TextField("예: 효자 아트홀", text: $name).autocorrectionDisabled().padding(16)
                        .background(HearV3.surface, in: RoundedRectangle(cornerRadius: 14))
                    if let error { Text(error).foregroundStyle(.red).font(.callout) }
                }.padding(20).padding(.top, 24)
            }.v3Screen().navigationTitle(venue == nil ? "새 공간" : "공간 이름 수정").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("닫기", systemImage: "chevron.left") { dismiss() }.labelStyle(.iconOnly).disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button("저장", systemImage: "checkmark", action: save).labelStyle(.iconOnly).buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black).disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80) }
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
