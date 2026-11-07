import SwiftUI
import HearIAmCore

/// Performance folders contain reference scenes and independently saved scans.
struct PerformanceLibraryView: View {
    @ObservedObject var library: StageLibrary
    @Binding var selectedPerformanceID: UUID?
    let onStartGuidance: (UUID) -> Void
    @State private var path: [UUID] = []
    @State private var query = ""
    @State private var creating = false
    @State private var alphabetical = false
    @Environment(\.hearChangeRole) private var changeRole

    private var folders: [PerformanceFolder] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = library.performanceFolders.filter {
            search.isEmpty || $0.name.localizedStandardContains(search) || $0.notes.localizedStandardContains(search)
        }
        return alphabetical ? matches.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } : matches
    }
    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("공연 리스트").font(.title.bold()).accessibilityAddTraits(.isHeader)
                            Spacer()
                            Menu {
                                Button("날짜순") { alphabetical = false }
                                Button("이름순") { alphabetical = true }
                            } label: {
                                HStack(spacing: 4) { Text(alphabetical ? "이름순" : "날짜순"); Image(systemName: "chevron.down") }
                                    .font(.subheadline).foregroundStyle(.secondary).frame(minHeight: 44)
                            }.accessibilityLabel("공연 정렬")
                        }.padding(.horizontal, 4)
                        PerformanceSearchField(text: $query, prompt: "공연 이름 또는 상세정보 검색")
                    }
                    if library.loading && folders.isEmpty {
                        ProgressView("공연을 불러오는 중이에요").frame(maxWidth: .infinity, minHeight: 260)
                    } else if folders.isEmpty {
                        VStack(spacing: 20) {
                            Image("PerformanceEmpty").resizable().scaledToFit().frame(width: 60, height: 60).accessibilityHidden(true)
                            Text(query.isEmpty ? "생성된 공연이\n없습니다" : "검색한 공연이\n없습니다")
                                .font(.title3.weight(.semibold)).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 360)
                    } else {
                        LazyVStack(spacing: 6) {
                            ForEach(folders) { folder in
                                NavigationLink(value: folder.id) {
                                    PerformanceFolderRow(name: folder.name, date: folder.updatedAt,
                                                         count: library.scans(in: folder.id).count)
                                }.buttonStyle(.plain).accessibilityIdentifier("performance.folder.\(folder.id.uuidString)")
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
                }.padding(.horizontal, 16).padding(.top, 28).padding(.bottom, 24)
            }.v3Screen()
                .hearTopBar(nil) {
                    Button { changeRole?() } label: { HearTopButtonLabel(systemImage: "house") }
                        .buttonStyle(.plain).accessibilityLabel("역할 선택으로 돌아가기")
                } trailing: {
                    Button { creating = true } label: { HearTopButtonLabel(systemImage: "plus", prominent: true) }
                        .buttonStyle(.plain).accessibilityLabel("새 공연 만들기").accessibilityIdentifier("performance.create")
                }
                .navigationDestination(for: UUID.self) { id in
                    PerformanceDetailView(library: library, performanceID: id, onStartGuidance: onStartGuidance)
                }
                .refreshable { await library.refresh() }
                .sheet(isPresented: $creating) { PerformanceEditorSheet(library: library) { id in path.append(id) }.suspendsVoiceWake() }
        }.v3Screen().onAppear { openRequestedFolder() }
            .onChange(of: selectedPerformanceID) { openRequestedFolder() }
            .onChange(of: library.performanceFolders.map(\.id)) { openRequestedFolder() }
    }
    private func openRequestedFolder() {
        guard let id = selectedPerformanceID, library.performanceFolders.contains(where: { $0.id == id }) else { return }
        path = [id]; selectedPerformanceID = nil
    }
}

/// The inline search surface in the performance and space lists (Figma 761:11415).
struct PerformanceSearchField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(.secondary)
                TextField(prompt, text: $text).font(.subheadline).autocorrectionDisabled()
                    .textInputAutocapitalization(.never).submitLabel(.search).focused($focused)
            }.padding(.horizontal, 16).frame(minHeight: 48)
                .liquidGlass(Capsule()).overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            if !text.isEmpty {
                Button { text = ""; focused = false } label: { Image(systemName: "xmark").font(.title3) }
                    .buttonStyle(.bordered).buttonBorderShape(.circle).accessibilityLabel("검색 지우기")
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
    @Environment(\.dismiss) private var dismiss
    init(library: StageLibrary, folder: PerformanceFolder? = nil, onSaved: @escaping (UUID) -> Void) {
        self.library = library; self.folder = folder; self.onSaved = onSaved
        _name = State(initialValue: folder?.name ?? ""); _notes = State(initialValue: folder?.notes ?? "")
    }
    private var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80 && notes.count <= 2000 }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("예: Lion King", text: $name).autocorrectionDisabled().accessibilityIdentifier("performance.editor.name")
                        .padding(.vertical, 4)
                } header: { Text("공연 이름").font(.title3.weight(.semibold)).foregroundStyle(HearV3.text).textCase(nil) }
                .listRowBackground(HearV3.surface)
                Section {
                    TextField("공연을 간단히 설명해주세요", text: $notes, axis: .vertical).lineLimit(3...8)
                        .padding(.vertical, 4).accessibilityIdentifier("performance.editor.notes")
                } header: { Text("공연 상세정보").font(.title3.weight(.semibold)).foregroundStyle(HearV3.text).textCase(nil) }
                .listRowBackground(HearV3.surface)
                if name.count > 80 || notes.count > 2000 {
                    Text("공연 이름은 80자, 상세정보는 2000자 이내로 입력해주세요.").font(.caption).foregroundStyle(.orange).listRowBackground(HearV3.canvas)
                }
                if let error { Text(error).foregroundStyle(.red).listRowBackground(HearV3.canvas) }
            }.scrollContentBackground(.hidden).v3Screen()
                .navigationTitle(folder == nil ? "공연 생성하기" : "공연 정보").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "chevron.backward") }.disabled(busy).accessibilityLabel("닫기") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: save) { if busy { ProgressView() } else { Image(systemName: "checkmark") } }
                            .buttonStyle(.borderedProminent).tint(HearV3.text).foregroundStyle(HearV3.canvas)
                            .disabled(busy || !valid).accessibilityLabel("공연 저장").accessibilityIdentifier("performance.editor.save")
                    }
                }.interactiveDismissDisabled(busy)
        }.v3Screen()
    }
    private func save() {
        guard valid, !busy else { return }
        busy = true; error = nil
        Task {
            do {
                let id: UUID
                if let folder { try await library.updatePerformance(id: folder.id, name: name, notes: notes); id = folder.id }
                else { id = try await library.createPerformance(name: name, notes: notes).id }
                dismiss(); onSaved(id)
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
