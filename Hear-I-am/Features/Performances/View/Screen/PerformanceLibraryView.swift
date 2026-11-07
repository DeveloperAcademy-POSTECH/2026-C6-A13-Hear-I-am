import SwiftUI
import HearIAmCore

/// Performance folders contain reference scenes and independently saved scans. Figma 공연 관리 (971:31947 ·
/// 971:32030 · 971:32093): the title, the search field and the rows, with a sort-and-filter menu (971:31766) next
/// to the + at the top.
struct PerformanceLibraryView: View {
    @ObservedObject var library: StageLibrary
    @Binding var selectedPerformanceID: UUID?
    let onStartGuidance: (UUID) -> Void
    @State private var path: [UUID] = []
    @State private var query = ""
    @State private var creating = false
    @State private var sort = PerformanceSort.newest
    @State private var period = PerformancePeriod.all
    /// Venue names to keep; empty keeps every performance.
    @State private var venueFilter: Set<String> = []
    @State private var choosingVenues = false
    @State private var deleting: PerformanceFolder?
    @State private var error: String?
    @Environment(\.hearChangeRole) private var changeRole

    private var folders: [PerformanceFolder] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let since = period.days.map { Date().addingTimeInterval(-Double($0) * 86_400) }
        let matches = library.performanceFolders.filter { folder in
            (search.isEmpty || folder.name.localizedStandardContains(search) || folder.notes.localizedStandardContains(search))
                && (venueFilter.isEmpty || folder.venues.contains { venueFilter.contains($0.name) })
                && (since.map { folder.updatedAt >= $0 } ?? true)
        }
        switch sort {
        case .newest: return matches.sorted { $0.updatedAt > $1.updatedAt }
        case .oldest: return matches.sorted { $0.updatedAt < $1.updatedAt }
        case .name: return matches.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
    private var filtering: Bool { !query.isEmpty || !venueFilter.isEmpty || period != .all }
    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("공연 리스트").font(HearFont.pretendard(.semibold, size: 28)).foregroundStyle(.white)
                            .padding(.horizontal, 5).accessibilityAddTraits(.isHeader)
                        PerformanceSearchField(text: $query, prompt: "공연 이름 또는 상세정보 검색")
                    }
                    if library.loading && folders.isEmpty {
                        ProgressView("공연을 불러오는 중이에요").frame(maxWidth: .infinity, minHeight: 260)
                    } else if folders.isEmpty {
                        // 971:32030: the stroke logo over the line, in the middle of what is left of the screen.
                        VStack(spacing: 20) {
                            Image("PerformanceEmpty").resizable().scaledToFit().frame(width: 60, height: 60).accessibilityHidden(true)
                            Text(filtering ? "찾는 공연이\n없습니다" : "생성된 공연이\n없습니다")
                                .font(HearFont.pretendard(.semibold, size: 20)).multilineTextAlignment(.center)
                                .foregroundStyle(HearV3.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 420)
                    } else {
                        LazyVStack(spacing: 6) {
                            // 971:31947: slide a row left to delete it; the same confirmation as on its page follows.
                            ForEach(folders) { folder in
                                HearSwipeDeleteRow(onOpen: { path.append(folder.id) }, onDelete: { deleting = folder }) {
                                    PerformanceFolderRow(name: folder.name, date: folder.updatedAt,
                                                         count: library.scans(in: folder.id).count)
                                }.accessibilityIdentifier("performance.folder.\(folder.id.uuidString)")
                            }
                        }
                    }
                    if !library.unassignedScans.isEmpty {
                        NavigationLink {
                            PerformanceScanSelectionView(library: library, title: "미분류 무대", scanIDs: [], onlyUnassigned: true, onStartGuidance: onStartGuidance)
                        } label: {
                            HStack { Label("미분류 무대", systemImage: "tray"); Spacer(); Text("\(library.unassignedScans.count)"); Image(systemName: "chevron.right") }
                                .font(.subheadline).padding(20).background(HearV3.surface, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 24)
            }
            #if DEBUG
            .defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("--scroll-bottom") ? .bottom : .top)
            #endif
            .v3Screen()
                .hearTopBar(nil) {
                    Button { changeRole?() } label: { HearTopButtonLabel(systemImage: "house") }
                        .buttonStyle(.plain).accessibilityLabel("역할 선택으로 돌아가기")
                } trailing: {
                    filterMenu
                    Button { creating = true } label: { HearTopButtonLabel(systemImage: "plus", prominent: true) }
                        .buttonStyle(.plain).accessibilityLabel("새 공연 만들기").accessibilityIdentifier("performance.create")
                }
                .navigationDestination(for: UUID.self) { id in
                    PerformanceDetailView(library: library, performanceID: id, onStartGuidance: onStartGuidance)
                }
                .refreshable { await library.refresh() }
                .sheet(isPresented: $creating) { PerformanceEditorSheet(library: library) { id in path.append(id) }.suspendsVoiceWake() }
                .sheet(isPresented: $choosingVenues) {
                    PerformanceVenueFilterSheet(names: venueNames, selection: venueFilter) { venueFilter = $0 }
                }
                .hearConfirm("‘\(deleting?.name ?? "")’ 공연 폴더를 삭제할까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                             message: "기본 동선과 공연 및 연습 공간이 함께 삭제돼요.\n스캔한 무대와 사진은 미분류로 남아요.") {
                    guard let id = deleting?.id else { return }
                    Task { do { try await library.deletePerformance(id) } catch { self.error = error.localizedDescription } }
                }
                .alert("삭제하지 못했어요", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("확인", role: .cancel) { error = nil }
                } message: { Text(error ?? "") }
        }.v3Screen().onAppear { openRequestedFolder() }
            .onChange(of: selectedPerformanceID) { openRequestedFolder() }
            .onChange(of: library.performanceFolders.map(\.id)) { openRequestedFolder() }
    }
    /// Every venue name used by any performance, once each.
    private var venueNames: [String] {
        Array(Set(library.performanceFolders.flatMap(\.venues).map(\.name))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    /// 971:31766: sort, venue and period, each a section of the system menu.
    private var filterMenu: some View {
        HearSortFilterMenu(sort: $sort, period: $period, venueCount: venueFilter.count) { choosingVenues = true }
    }
    private func openRequestedFolder() {
        guard let id = selectedPerformanceID, library.performanceFolders.contains(where: { $0.id == id }) else { return }
        path = [id]; selectedPerformanceID = nil
    }
}

/// The sort-and-filter button shared by the performance list and the records (971:31766 · 971:31052): sort, venue
/// and period in one system menu. While anything differs from the default the button fills white (971:21459).
struct HearSortFilterMenu: View {
    @Binding var sort: PerformanceSort
    @Binding var period: PerformancePeriod
    let venueCount: Int
    let chooseVenues: () -> Void
    private var active: Bool { sort != .newest || period != .all || venueCount > 0 }
    var body: some View {
        Menu {
            Section("정렬") {
                Picker("정렬", selection: $sort) {
                    ForEach(PerformanceSort.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.inline).labelsHidden()
            }
            Section("장소") {
                Button(action: chooseVenues) {
                    Text("장소 선택…")
                    Text(venueCount == 0 ? "전체 장소" : "\(venueCount)곳 선택")
                }
            }
            Section("기간") {
                Picker("기간", selection: $period) {
                    ForEach(PerformancePeriod.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.inline).labelsHidden()
            }
        } label: {
            ZStack {
                HearTopButtonLabel(systemImage: "line.3.horizontal.decrease")
                if active {
                    Image(systemName: "line.3.horizontal.decrease").font(.system(size: 16, weight: .semibold)).foregroundStyle(.black)
                        .frame(width: 34, height: 34).background(.white, in: Circle())
                }
            }.animation(.snappy(duration: 0.2), value: active)
        }.buttonStyle(.plain).accessibilityLabel("정렬과 필터").accessibilityValue(active ? "적용됨" : "")
    }
}

enum PerformanceSort: CaseIterable {
    case newest, oldest, name
    var title: String { switch self { case .newest: "최신순"; case .oldest: "오래된순"; case .name: "공연 이름순" } }
}

enum PerformancePeriod: CaseIterable {
    case all, week, month
    var title: String { switch self { case .all: "전체 기간"; case .week: "최근 7일"; case .month: "최근 30일" } }
    var days: Int? { switch self { case .all: nil; case .week: 7; case .month: 30 } }
}

/// 971:31837: the venues to show, from every performance, with 「전체 장소」 first to clear the choice.
struct PerformanceVenueFilterSheet: View {
    let names: [String]
    let onDone: (Set<String>) -> Void
    @State private var selection: Set<String>
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    /// No filter means every venue, so it opens with all of them checked.
    init(names: [String], selection: Set<String>, onDone: @escaping (Set<String>) -> Void) {
        self.names = names; self.onDone = onDone
        _selection = State(initialValue: selection.isEmpty ? Set(names) : selection.intersection(names))
    }
    private var allChecked: Bool { !names.isEmpty && Set(names).isSubset(of: selection) }
    private var shown: [String] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty ? names : names.filter { $0.localizedStandardContains(search) }
    }
    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PerformanceSearchField(text: $query, prompt: "장소 검색")
                    Text("\(selection.count)곳 선택됨")
                        .font(HearFont.pretendard(.regular, size: 13)).foregroundStyle(HearV3.secondary)
                        .padding(.top, 16).padding(.bottom, 12)
                    VStack(spacing: 0) {
                        // 「전체 장소」 checks every venue, and unchecks them all when they already are.
                        if query.isEmpty { row("전체 장소", checked: allChecked) { selection = allChecked ? [] : Set(names) } }
                        ForEach(shown, id: \.self) { name in
                            row(name, checked: selection.contains(name)) {
                                if selection.contains(name) { selection.remove(name) } else { selection.insert(name) }
                            }
                        }
                        if names.isEmpty {
                            Text("등록된 장소가 없어요").font(.subheadline).foregroundStyle(HearV3.secondary).padding(.vertical, 24)
                        }
                    }.padding(.horizontal, 16)
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
            }
                .hearTopBar("장소 선택", sheet: true) {
                    Button { dismiss() } label: { HearTopButtonLabel(systemImage: "xmark") }.buttonStyle(.plain).accessibilityLabel("닫기")
                } trailing: {
                    // Every venue checked is the same as no filter, which also keeps venues added later.
                    Button { onDone(allChecked ? [] : selection); dismiss() } label: { HearTopButtonLabel(systemImage: "checkmark", prominent: true) }
                        .buttonStyle(.plain).disabled(selection.isEmpty).opacity(selection.isEmpty ? 0.4 : 1).accessibilityLabel("선택 완료")
                }
                .hearSheet()
    }
    private func row(_ title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.body).foregroundStyle(.white)
                Spacer()
                if checked { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(.white) }
            }.frame(height: 52).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5) }
            .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

/// The inline search surface in the performance and space lists (Figma 761:11415).
struct PerformanceSearchField: View {
    @Binding var text: String
    let prompt: String
    static let grey = Color(red: 118/255, green: 118/255, blue: 118/255)
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 12) {
            // Figma 971:31959 · 971:32437: a 48pt liquid-glass capsule tinted white 5%, the grey glass and prompt in Pretendard 16.
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(Self.grey).frame(width: 24, height: 24)
                TextField(prompt, text: $text, prompt: Text(prompt).foregroundStyle(Self.grey))
                    .font(HearFont.pretendard(.regular, size: 16)).foregroundStyle(.white).autocorrectionDisabled()
                    .textInputAutocapitalization(.never).submitLabel(.search).focused($focused)
            }.padding(.horizontal, 16).frame(minHeight: 48)
                .liquidGlass(Capsule(), tint: .white.opacity(0.05))
            if !text.isEmpty {
                Button { text = ""; focused = false } label: { HearTopButtonLabel(systemImage: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("검색 지우기")
            }
        }.animation(.easeInOut(duration: 0.18), value: text.isEmpty)
    }
}

struct PerformanceFolderRow: View {
    let name: String
    let date: Date
    let count: Int
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yy.MM.dd"
        return formatter
    }()
    static func dateLabel(_ date: Date) -> String { dateFormatter.string(from: date) }
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.body.weight(.medium)).lineLimit(2)
                Text(Self.dateLabel(date))
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text("\(count)").font(.caption).monospacedDigit().padding(5)
                .background(.white.opacity(0.10), in: Circle()).accessibilityLabel("스캔 파일 \(count)개")
            Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).accessibilityHidden(true)
        }.padding(.horizontal, 20).padding(.vertical, 14).frame(minHeight: 70)
            .background(HearV3.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
    }
}

struct PerformanceEditorSheet: View {
    @ObservedObject var library: StageLibrary
    let folder: PerformanceFolder?
    let onSaved: (UUID) -> Void
    @State private var name: String
    @State private var notes: String
    @State private var busy = false
    @State private var error: String?
    @State private var venue: String?
    @State private var addingVenue = false
    @State private var newVenue = ""
    @Environment(\.dismiss) private var dismiss
    init(library: StageLibrary, folder: PerformanceFolder? = nil, onSaved: @escaping (UUID) -> Void) {
        self.library = library; self.folder = folder; self.onSaved = onSaved
        _name = State(initialValue: folder?.name ?? ""); _notes = State(initialValue: folder?.notes ?? "")
    }
    private var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80 && notes.count <= 2000 }
    /// Every venue name already used by a performance, for the new performance's 「공연 및 연습 장소」.
    private var venueNames: [String] {
        Array(Set(library.performanceFolders.flatMap(\.venues).map(\.name))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    var body: some View {
        // Figma 971:32062: 공연 이름 and, for a new performance, 공연 상세정보 holding its venue. An existing one keeps
        // its description here; its venues are managed on its own page.
            ScrollView {
                VStack(alignment: .leading, spacing: 33) {
                    VStack(alignment: .leading, spacing: 12) {
                        header("공연 이름")
                        TextField("", text: $name, prompt: Text("ex. 소말리아 해적선").foregroundStyle(PerformanceSearchField.grey))
                            .font(HearFont.pretendard(.regular, size: 16)).foregroundStyle(.white)
                            .autocorrectionDisabled().accessibilityIdentifier("performance.editor.name")
                            .padding(.horizontal, 16).frame(height: 48)
                            .background(Self.field, in: Capsule())
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        header("공연 상세정보")
                        if folder == nil {
                            venueRow
                        } else {
                            TextField("", text: $notes, prompt: Text("공연을 간단히 설명해주세요").foregroundStyle(PerformanceSearchField.grey), axis: .vertical)
                                .lineLimit(3...8).font(HearFont.pretendard(.regular, size: 16)).foregroundStyle(.white)
                                .padding(16).background(Self.field, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                                .accessibilityIdentifier("performance.editor.notes")
                        }
                    }
                    if name.count > 80 || notes.count > 2000 {
                        Text("공연 이름은 80자, 상세정보는 2000자 이내로 입력해주세요.").font(.caption).foregroundStyle(.orange)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }.padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 24)
            }
                .hearTopBar(folder == nil ? "공연 생성하기" : "공연 정보", sheet: true) {
                    Button { dismiss() } label: { HearTopButtonLabel(systemImage: "xmark") }
                        .buttonStyle(.plain).disabled(busy).accessibilityLabel("닫기")
                } trailing: {
                    Button(action: save) {
                        if busy { ProgressView().frame(width: 44, height: 44) }
                        else { HearTopButtonLabel(systemImage: "checkmark", prominent: true).opacity(valid ? 1 : 0.4) }
                    }.buttonStyle(.plain).disabled(busy || !valid)
                        .accessibilityLabel("공연 저장").accessibilityIdentifier("performance.editor.save")
                }
                .interactiveDismissDisabled(busy)
                .alert("새 장소", isPresented: $addingVenue) {
                    TextField("장소 이름", text: $newVenue)
                    Button("취소", role: .cancel) { newVenue = "" }
                    Button("추가") {
                        let trimmed = newVenue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { venue = trimmed }
                        newVenue = ""
                    }
                }
                .hearSheet()
    }
    private static let field = Color(red: 28/255, green: 28/255, blue: 30/255)
    private func header(_ text: String) -> some View {
        Text(text).font(HearFont.pretendard(.semibold, size: 20)).foregroundStyle(.white).padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
    /// The grouped row (971:32080): 「공연 및 연습 장소」 stays put and only the value on the right opens the choices,
    /// the way a menu picker row does, so the menu grows out of 「선택 안 함」 instead of out of the whole row.
    private var venueRow: some View {
        HStack(spacing: 8) {
            Text("공연 및 연습 장소").font(.body).foregroundStyle(.white)
            Spacer(minLength: 8)
            Menu {
                Picker("공연 및 연습 장소", selection: $venue) {
                    Text("선택 안 함").tag(String?.none)
                    ForEach(venueNames + [venue].compactMap { $0 }.filter { !venueNames.contains($0) }, id: \.self) { name in Text(name).tag(Optional(name)) }
                }.pickerStyle(.inline)
                Section { Button("새 장소 추가…", systemImage: "plus") { addingVenue = true } }
            } label: {
                HStack(spacing: 8) {
                    Text(venue ?? "선택 안 함").font(.body).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 14, weight: .medium))
                }.foregroundStyle(Self.detail).frame(minHeight: 44).contentShape(Rectangle())
            }.accessibilityLabel("공연 및 연습 장소, \(venue ?? "선택 안 함")")
        }.padding(.horizontal, 19).frame(height: 52)
            .background(Self.field, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
    private static let detail = Color(red: 235/255, green: 235/255, blue: 245/255).opacity(0.7)
    private func save() {
        guard valid, !busy else { return }
        busy = true; error = nil
        Task {
            do {
                let id: UUID
                if let folder { try await library.updatePerformance(id: folder.id, name: name, notes: notes); id = folder.id }
                else {
                    id = try await library.createPerformance(name: name, notes: notes).id
                    if let venue { try await library.createVenue(name: venue, in: id) }
                }
                dismiss(); onSaved(id)
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
