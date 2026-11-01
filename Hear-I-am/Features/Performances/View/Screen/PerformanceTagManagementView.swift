import SwiftUI
import HearIAmCore

struct PerformanceTagManagementView:View {
    @ObservedObject var library:StageLibrary
    let performanceID:UUID
    var onStartGuidance:((UUID)->Void)?
    @State private var query=""
    @State private var creating=false
    private var folder:PerformanceFolder? {library.performanceFolders.first {$0.id==performanceID}}
    var body:some View {
        List {
            if let folder {
                Section {
                    Text(folder.name).font(.title2.bold())
                    Text("공연장 태그 \(folder.venues.count)개 · 저장한 무대 \(library.scans(in:performanceID).count)개").font(.subheadline).foregroundStyle(.secondary)
                }.listRowBackground(HearV3.canvas)
                Section {
                    NavigationLink {
                        PerformanceScanSelectionView(library:library,title:"공연장 미지정",scanIDs:[],performanceID:performanceID,onStartGuidance:onStartGuidance)
                    } label:{
                        HStack {Label("미지정 무대",systemImage:"tray");Spacer();Text("\(library.scans(in:performanceID,includeAllVenues:false).count)개").foregroundStyle(.secondary)}.frame(minHeight:48)
                    }
                }
                Section("공연장 태그") {
                    ForEach(folder.venues.filter {query.isEmpty || $0.name.localizedStandardContains(query)}) {venue in
                        NavigationLink {
                            PerformanceScanSelectionView(library:library,title:venue.name,scanIDs:[],performanceID:performanceID,venueID:venue.id,onStartGuidance:onStartGuidance)
                        } label:{
                            VStack(alignment:.leading,spacing:6) {
                                Text(venue.name).font(.headline)
                                Text("저장한 무대 \(library.scans(in:performanceID,venueID:venue.id,includeAllVenues:false).count)개").font(.caption).foregroundStyle(.secondary)
                            }.frame(minHeight:48)
                        }
                    }
                    Button("새 공연장 태그",systemImage:"plus") {creating=true}.frame(minHeight:48)
                }
                Section {Text("태그를 선택해 연결된 무대를 확인하고 분류를 바꿀 수 있어요. 태그를 삭제해도 무대와 사진, 기록은 남아요.").font(.footnote).foregroundStyle(.secondary)}
            }
        }.scrollContentBackground(.hidden).v3Screen().navigationTitle("공연장 태그 관리").navigationBarTitleDisplayMode(.inline)
            .searchable(text:$query,prompt:"공연장 이름 검색")
            .toolbar {ToolbarItem(placement:.topBarTrailing) {Button {creating=true} label:{Image(systemName:"plus")}.accessibilityLabel("새 공연장 태그")}}
            .sheet(isPresented:$creating) {VenueEditorSheet(library:library,performanceID:performanceID) {_ in}.suspendsVoiceWake()}
    }
}

/// A live source is used for a venue or the unassigned list, so moved scans disappear immediately.
struct PerformanceScanSelectionView:View {
    @ObservedObject var library:StageLibrary
    let title:String
    let scanIDs:[UUID]
    var performanceID:UUID?=nil
    var venueID:UUID?=nil
    var onlyUnassigned=false
    var onStartGuidance:((UUID)->Void)?
    @State private var selected:Set<UUID>=[]
    @State private var classifying=false
    @State private var classificationIDs:[UUID]=[]
    @State private var renaming=false
    @State private var deleting=false
    @State private var error:String?
    @State private var busy=false
    @Environment(\.dismiss) private var dismiss
    private var venue:PerformanceVenueTag? {library.performanceFolders.first {$0.id==performanceID}?.venues.first {$0.id==venueID}}
    private var scans:[ScanManifest] {
        if let performanceID {return library.scans(in:performanceID,venueID:venueID,includeAllVenues:false)}
        if onlyUnassigned {return library.unassignedScans}
        return library.records.filter {scanIDs.contains($0.id)}
    }
    var body:some View {
        List {
            Section {
                Text(venue?.name ?? title).font(.title2.bold())
                Text("저장한 무대 \(scans.count)개 · \(selected.count)개 선택됨").font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Button(selected.count == scans.count && !scans.isEmpty ? "선택 해제" : "모두 선택") {
                        selected=selected.count == scans.count ? [] : Set(scans.map(\.id))
                    }
                    Spacer()
                    if venue != nil {Button("이름 수정") {renaming=true};Button("태그 삭제",role:.destructive) {deleting=true}}
                }.frame(minHeight:44)
            }.listRowBackground(HearV3.canvas)
            Section("연결된 무대") {
                if scans.isEmpty {Text("아직 연결된 무대가 없어요.").foregroundStyle(.secondary)}
                ForEach(scans,id:\.id) {scan in
                    VStack(alignment:.leading,spacing:10) {
                        Button {if selected.contains(scan.id) {selected.remove(scan.id)} else {selected.insert(scan.id)}} label:{
                            HStack(spacing:12) {
                                Image(systemName:selected.contains(scan.id) ? "checkmark.circle.fill" : "circle").font(.title3)
                                VStack(alignment:.leading,spacing:5) {
                                    Text(scan.name).font(.headline)
                                    Text("\(scan.date.formatted(.dateTime.month().day().hour().minute())) · \(scan.route?.points.count ?? 0)지점").font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth:.infinity,alignment:.leading)
                            }.frame(minHeight:48).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("\(scan.name) 선택").accessibilityAddTraits(selected.contains(scan.id) ? .isSelected : [])
                        HStack {
                            NavigationLink("무대 보기") {SavedStagePreview(record:scan,store:library.scans).onDisappear {Task {await library.refresh()}}}
                            Spacer()
                            if let onStartGuidance {
                                Button {onStartGuidance(scan.id)} label:{Label("안내 시작",systemImage:"arrow.up.right")}.buttonStyle(.bordered)
                                    .disabled(!scan.supportsAlignment || scan.route == nil)
                            }
                        }.font(.subheadline)
                    }.padding(.vertical,6)
                }
            }
            Section {Text("같은 공연장에서 스캔한 무대를 선택하고 공연장 태그를 한 번에 바꿀 수 있어요. 동선, 기물, 사진과 기록은 유지됩니다.").font(.footnote).foregroundStyle(.secondary)}
        }.scrollContentBackground(.hidden).v3Screen().navigationTitle(venue?.name ?? title).navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge:.bottom) {Button("선택한 \(selected.count)개 분류 변경") {classificationIDs=Array(selected);classifying=true}.buttonStyle(V3PrimaryButtonStyle()).disabled(selected.isEmpty || busy).padding(20).background(HearV3.canvas)}
            .sheet(isPresented:$classifying) {StageClassificationView(library:library,scanIDs:classificationIDs,initialPerformanceID:performanceID,initialVenueID:venueID) {_ in selected=[]}.suspendsVoiceWake()}
            .sheet(isPresented:$renaming) {if let performanceID,let venue {VenueEditorSheet(library:library,performanceID:performanceID,venue:venue) {_ in}.suspendsVoiceWake()}}
            .confirmationDialog("태그만 삭제할까요?",isPresented:$deleting,titleVisibility:.visible) {
                Button("공연장 태그 삭제",role:.destructive) {deleteTag()};Button("취소",role:.cancel) {}
            } message:{Text("연결된 \(scans.count)개 무대는 이 공연의 ‘공연장 미지정’으로 이동해요. 무대와 사진, 기록은 삭제되지 않아요.")}
            .alert("변경하지 못했어요",isPresented:Binding(get:{error != nil},set:{if !$0 {error=nil}})) {Button("확인",role:.cancel) {error=nil}} message:{Text(error ?? "")}
            .onChange(of:scans.map(\.id)) {_,ids in selected.formIntersection(ids)}
    }
    private func deleteTag() {
        guard let performanceID,let venueID else {return};busy=true
        Task {do {try await library.deleteVenue(venueID,in:performanceID);dismiss()} catch {self.error=error.localizedDescription};busy=false}
    }
}
