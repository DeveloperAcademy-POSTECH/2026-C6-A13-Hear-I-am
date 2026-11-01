import SwiftUI
import HearIAmCore

/// Performance folders own a reference plan and venue-tagged scans. Scans remain independently durable.
struct PerformanceLibraryView: View {
    @ObservedObject var library: StageLibrary
    @Binding var selectedPerformanceID: UUID?
    let onStartGuidance: (UUID) -> Void
    @State private var path: [UUID] = []
    @State private var query = ""
    @State private var creating = false
    @State private var alphabetical = false
    private var folders: [PerformanceFolder] {
        let matches=library.performanceFolders.filter {query.isEmpty || $0.name.localizedStandardContains(query) || $0.notes.localizedStandardContains(query)}
        return alphabetical ? matches.sorted {$0.name.localizedStandardCompare($1.name) == .orderedAscending} : matches
    }
    var body: some View {
        NavigationStack(path:$path) {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    VStack(alignment:.leading,spacing:6) {
                        Text("준비 중인 공연").font(.title2.bold())
                        Text("동선과 무대를 공연별로 정리해요.").font(.subheadline).foregroundStyle(HearV3.secondary)
                    }
                    HStack {
                        Text("공연 \(folders.count)개").font(.subheadline.weight(.semibold))
                        Spacer()
                        Menu {
                            Button("최근 수정순") {alphabetical=false}
                            Button("이름순") {alphabetical=true}
                            Divider()
                            Button("목록 새로고침",systemImage:"arrow.clockwise") {Task {await library.refresh()}}
                                .disabled(library.loading)
                        } label: {Label(alphabetical ? "이름순" : "최근 수정순",systemImage:"chevron.down").font(.caption).frame(minHeight:44)}
                    }
                    if library.loading && folders.isEmpty {ProgressView("공연을 불러오는 중이에요").frame(maxWidth:.infinity)}
                    else if folders.isEmpty {
                        ContentUnavailableView(query.isEmpty ? "첫 공연을 만들어보세요" : "검색한 공연이 없어요",systemImage:"folder",description:Text(query.isEmpty ? "오른쪽 위 + 버튼으로 공연을 만들고 동선과 무대를 모아보세요." : "다른 이름으로 검색해주세요."))
                    } else {
                        LazyVStack(spacing:12) {
                            ForEach(folders) {folder in
                                NavigationLink(value:folder.id) {
                                    HStack(spacing:14) {
                                        Image(systemName:"folder").font(.title3)
                                        VStack(alignment:.leading,spacing:6) {
                                            Text(folder.name).font(.headline)
                                            Text(summary(folder)).font(.caption).foregroundStyle(HearV3.secondary)
                                        }.frame(maxWidth:.infinity,alignment:.leading)
                                        Image(systemName:"chevron.right").font(.caption).accessibilityHidden(true)
                                    }.v3Card(inset:20).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityIdentifier("performance.folder.\(folder.id.uuidString)")
                            }
                        }
                    }
                    if !library.unassignedScans.isEmpty {
                        NavigationLink {
                            PerformanceScanSelectionView(library:library,title:"미분류 무대",scanIDs:[],onlyUnassigned:true,onStartGuidance:onStartGuidance)
                        } label: {
                            HStack {Label("미분류 무대",systemImage:"tray");Spacer();Text("\(library.unassignedScans.count)개");Image(systemName:"chevron.right")}.font(.subheadline).v3Card(inset:20)
                        }.buttonStyle(.plain)
                    }
                }.padding(20)
            }.v3Screen().navigationTitle("공연 관리").navigationBarTitleDisplayMode(.inline)
                .searchable(text:$query,placement:.navigationBarDrawer(displayMode:.always),prompt:"공연 이름 검색")
                .toolbar {ToolbarItem(placement:.topBarTrailing) {Button {creating=true} label:{Image(systemName:"plus")}.accessibilityLabel("새 공연 만들기").accessibilityIdentifier("performance.create")}}
                .navigationDestination(for:UUID.self) {id in PerformanceDetailView(library:library,performanceID:id,onStartGuidance:onStartGuidance)}
                .refreshable {await library.refresh()}
                .sheet(isPresented:$creating) {PerformanceEditorSheet(library:library) {id in path.append(id)}.suspendsVoiceWake()}
        }.v3Screen().onAppear {openRequestedFolder()}
            .onChange(of:selectedPerformanceID) {openRequestedFolder()}
            .onChange(of:library.performanceFolders.map(\.id)) {openRequestedFolder()}
    }
    private func summary(_ folder: PerformanceFolder) -> String {
        let count=library.scans(in:folder.id).count
        if let id=folder.defaultPlanID,let plan=library.plans.first(where:{$0.id == id}) {
            return "기본 동선 \(plan.points.count)지점 · 저장한 무대 \(count)개"
        }
        return count == 0 ? "기본 동선 설정 전" : "저장한 무대 \(count)개 · 기본 동선 설정 전"
    }
    private func openRequestedFolder() {
        guard let id=selectedPerformanceID,library.performanceFolders.contains(where:{$0.id==id}) else {return}
        path=[id];selectedPerformanceID=nil
    }
}

struct PerformanceEditorSheet: View {
    @ObservedObject var library: StageLibrary
    let folder: PerformanceFolder?
    let onSaved: (UUID) -> Void
    @State private var name: String
    @State private var notes: String
    @State private var busy=false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(library:StageLibrary,folder:PerformanceFolder?=nil,onSaved:@escaping (UUID)->Void) {
        self.library=library;self.folder=folder;self.onSaved=onSaved
        _name=State(initialValue:folder?.name ?? "");_notes=State(initialValue:folder?.notes ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(folder == nil ? "어떤 공연을 준비하나요?" : "공연 정보를 수정해요").font(.title2.bold())
                    Text("공연의 이름과 설명은 목록과 음성 검색에 사용해요.").foregroundStyle(.secondary)
                }.listRowBackground(HearV3.canvas)
                Section("공연 이름") {TextField("예: Lion King",text:$name).autocorrectionDisabled()}
                Section("공연 설명 · 선택") {TextField("공연을 간단히 설명해주세요",text:$notes,axis:.vertical).lineLimit(3...6)}
                Section {Label("기본 동선과 공연장별 무대는 공연을 만든 뒤 추가할 수 있어요.",systemImage:"folder").font(.subheadline)}
                if let error {Section {Text(error).foregroundStyle(.red)}}
            }.scrollContentBackground(.hidden).v3Screen()
                .navigationTitle(folder == nil ? "새 공연" : "공연 정보").navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.cancellationAction) {Button("닫기",systemImage:"xmark") {dismiss()}.labelStyle(.iconOnly).disabled(busy)}}
                .safeAreaInset(edge:.bottom) {
                    Button(busy ? "저장 중…" : (folder == nil ? "공연 만들기" : "변경 내용 저장")) {save()}
                        .buttonStyle(V3PrimaryButtonStyle()).disabled(busy || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                        .padding(20).background(HearV3.canvas).accessibilityIdentifier("performance.editor.save")
                }.interactiveDismissDisabled(busy)
        }.v3Screen()
    }
    private func save() {
        busy=true;error=nil
        Task {
            do {
                let id:UUID
                if let folder {try await library.updatePerformance(id:folder.id,name:name,notes:notes);id=folder.id}
                else {id=try await library.createPerformance(name:name,notes:notes).id}
                dismiss();onSaved(id)
            } catch {self.error=error.localizedDescription}
            busy=false
        }
    }
}
