import SwiftUI
import HearIAmCore

struct PerformanceDetailView: View {
    @ObservedObject var library: StageLibrary
    let performanceID: UUID
    let onStartGuidance: (UUID) -> Void
    @State private var venue: PerformanceVenueFilter = .all
    @State private var editing=false
    @State private var editingPlan: PerformancePlan?
    @State private var linking=false
    @State private var deleting=false
    @State private var error:String?
    @State private var busy=false
    @Environment(\.dismiss) private var dismiss
    private var folder: PerformanceFolder? {library.performanceFolders.first {$0.id==performanceID}}
    private var scans:[ScanManifest] {
        switch venue {
        case .all: return library.scans(in:performanceID)
        case .unassigned: return library.scans(in:performanceID,includeAllVenues:false)
        case .venue(let id): return library.scans(in:performanceID,venueID:id,includeAllVenues:false)
        }
    }
    var body: some View {
        ScrollView {
            if let folder {
                VStack(alignment:.leading,spacing:26) {
                    VStack(alignment:.leading,spacing:6) {
                        Text(folder.name).font(.title.bold()).accessibilityAddTraits(.isHeader)
                        if !folder.notes.isEmpty {Text(folder.notes).font(.subheadline).foregroundStyle(HearV3.secondary)}
                    }
                    VStack(alignment:.leading,spacing:12) {
                        HStack {
                            Text("기본 동선").font(.title2.bold());Spacer()
                            Button(folder.defaultPlanID == nil ? "설정" : "편집") {editingPlan=library.referencePlan(for:performanceID)}
                                .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.large)
                        }
                        if let planID=folder.defaultPlanID,let plan=library.plans.first(where:{$0.id==planID}) {
                            VStack(alignment:.leading,spacing:12) {
                                HStack {
                                    Text("\(plan.points.count)지점 · 기물 \(plan.objects.count)개").font(.caption).foregroundStyle(HearV3.secondary)
                                    Spacer();Text("설정됨").font(.caption).foregroundStyle(HearV3.accent).padding(.horizontal,9).padding(.vertical,5).background(HearV3.accent.opacity(0.15),in:Capsule())
                                }
                                StageMap(points:plan.points,finished:plan.finished,objects:plan.objects,v3Style:true,objectFacings:plan.objectFacings).frame(height:190)
                                Text("공연장에 맞추기 전, 기준이 되는 동선이에요.").font(.caption).foregroundStyle(HearV3.secondary)
                            }.v3Card()
                        } else {
                            VStack(alignment:.leading,spacing:12) {
                                Label("아직 기본 동선이 없어요",systemImage:"map").font(.headline)
                                Text("공연에 사용할 경로와 기물 배치를 먼저 그려볼 수 있어요.").font(.subheadline).foregroundStyle(HearV3.secondary)
                                Button("기본 동선 설정") {editingPlan=library.referencePlan(for:performanceID)}.buttonStyle(.bordered)
                            }.v3Card()
                        }
                    }
                    VStack(alignment:.leading,spacing:14) {
                        HStack {Text("공연장별 무대").font(.title2.bold());Spacer();Button("연결") {linking=true}.buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.large)}
                        ScrollView(.horizontal,showsIndicators:false) {
                            HStack(spacing:8) {
                                venueChip("전체",.all)
                                ForEach(folder.venues) {tag in venueChip(tag.name,.venue(tag.id))}
                                venueChip("미지정",.unassigned)
                            }
                        }
                        if scans.isEmpty {
                            ContentUnavailableView("연결된 무대가 없어요",systemImage:"building.2",description:Text("스캔한 무대를 이 공연에 연결해주세요."))
                        } else {
                            LazyVStack(spacing:12) {
                                ForEach(scans,id:\.id) {scan in
                                    PerformanceStageCard(record:scan,venueName:library.catalog.venue(for:scan.id)?.name ?? "공연장 미지정",library:library,onStartGuidance:onStartGuidance)
                                }
                            }
                        }
                        NavigationLink {
                            PerformanceTagManagementView(library:library,performanceID:performanceID,onStartGuidance:onStartGuidance)
                        } label: {Text("공연장 태그 관리").font(.headline).frame(maxWidth:.infinity,minHeight:48).background(HearV3.raised,in:Capsule())}.buttonStyle(.plain)
                    }
                }.padding(20)
            } else {ContentUnavailableView("공연을 찾을 수 없어요",systemImage:"folder.badge.questionmark")}
        }.v3Screen().navigationTitle("공연 관리").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.topBarTrailing) {
                Menu {Button("공연 정보 수정",systemImage:"pencil") {editing=true};Button("공연 폴더 삭제",systemImage:"trash",role:.destructive) {deleting=true}} label:{Image(systemName:"ellipsis")}.accessibilityLabel("공연 관리 메뉴").disabled(busy)
            }}
            .sheet(isPresented:$editing) {if let folder {PerformanceEditorSheet(library:library,folder:folder) {_ in}.suspendsVoiceWake()}}
            .sheet(isPresented:$linking) {PerformanceLinkStagesView(library:library,performanceID:performanceID).suspendsVoiceWake()}
            .fullScreenCover(item:$editingPlan) {plan in PlanEditorView(initial:plan,library:library,performanceID:performanceID).suspendsVoiceWake()}
            .confirmationDialog("공연 폴더를 삭제할까요?",isPresented:$deleting,titleVisibility:.visible) {
                Button("공연 폴더 삭제",role:.destructive) {deleteFolder()};Button("취소",role:.cancel) {}
            } message:{Text("연결된 무대는 미분류로 보관합니다. 스캔, 사진과 안내 기록은 삭제하지 않아요.")}
            .alert("변경하지 못했어요",isPresented:Binding(get:{error != nil},set:{if !$0 {error=nil}})) {Button("확인",role:.cancel) {error=nil}} message:{Text(error ?? "")}
            .onChange(of:folder?.venues.map(\.id)) {_,ids in if case .venue(let id)=venue,ids?.contains(id) != true {venue = .all}}
    }
    private func venueChip(_ title:String,_ value:PerformanceVenueFilter) -> some View {
        Button {venue=value} label:{Text(title).font(.subheadline.weight(.medium)).padding(.horizontal,16).frame(minHeight:48).background(venue==value ? HearV3.text : HearV3.raised,in:Capsule()).foregroundStyle(venue==value ? HearV3.canvas : HearV3.text)}.buttonStyle(.plain).accessibilityAddTraits(venue==value ? .isSelected : [])
    }
    private func deleteFolder() {
        busy=true
        Task {do {try await library.deletePerformance(performanceID);dismiss()} catch {self.error=error.localizedDescription};busy=false}
    }
}

enum PerformanceVenueFilter: Hashable {case all,unassigned,venue(UUID)}

/// Pick existing durable scans before assigning them to this performance.
struct PerformanceLinkStagesView: View {
    @ObservedObject var library:StageLibrary
    let performanceID:UUID
    @State private var selected:Set<UUID>=[]
    @State private var query=""
    @State private var classifying=false
    @State private var classificationIDs:[UUID]=[]
    @Environment(\.dismiss) private var dismiss
    private var scans:[ScanManifest] {library.records.filter {query.isEmpty || $0.name.localizedStandardContains(query) || (library.catalog.folder(for:$0.id)?.name.localizedStandardContains(query) ?? false)}}
    var body:some View {
        NavigationStack {
            List {
                Section {Text("스캔한 무대를 선택해주세요. 다른 공연에 연결된 무대는 이 공연으로 옮겨집니다.").font(.subheadline).foregroundStyle(.secondary)}
                if scans.isEmpty {ContentUnavailableView("연결할 무대가 없어요",systemImage:"building.2",description:Text(query.isEmpty ? "스캔 탭에서 무대를 먼저 저장해주세요." : "다른 이름으로 검색해주세요."))}
                ForEach(scans,id:\.id) {scan in
                    Button {if selected.contains(scan.id) {selected.remove(scan.id)} else {selected.insert(scan.id)}} label:{
                        HStack {
                            VStack(alignment:.leading,spacing:5) {Text(scan.name);Text(library.catalog.folder(for:scan.id)?.name ?? "미분류 무대").font(.caption).foregroundStyle(.secondary)}
                            Spacer();Image(systemName:selected.contains(scan.id) ? "checkmark.circle.fill" : "circle")
                        }.frame(minHeight:48)
                    }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(scan.id) ? .isSelected : [])
                }
            }.scrollContentBackground(.hidden).v3Screen().navigationTitle("무대 연결").navigationBarTitleDisplayMode(.inline)
                .searchable(text:$query,prompt:"무대 또는 공연 이름 검색")
                .toolbar {ToolbarItem(placement:.cancellationAction) {Button("닫기",systemImage:"xmark") {dismiss()}.labelStyle(.iconOnly)}}
                .safeAreaInset(edge:.bottom) {Button("선택한 \(selected.count)개 연결") {classificationIDs=Array(selected);classifying=true}.buttonStyle(V3PrimaryButtonStyle()).disabled(selected.isEmpty).padding(20).background(HearV3.canvas)}
                .sheet(isPresented:$classifying) {StageClassificationView(library:library,scanIDs:classificationIDs,initialPerformanceID:performanceID) {_ in dismiss()}.suspendsVoiceWake()}
        }.v3Screen()
    }
}
