import SwiftUI
import HearIAmCore

struct RoomDetailView: View {
    let venue: SpaceVenue
    let room: VenueRoom
    @ObservedObject var library: StageLibrary
    @AppStorage("spaces.operatorTools") private var operatorTools=false
    @State private var request: SpacePreparationRequest?
    @State private var choosingPreparation=false
    @State private var connecting=false
    @State private var renameID: UUID?
    @State private var rename=""
    @State private var newestFirst=true
    @State private var guidanceStage: ScanManifest?
    private var performances: [ScanManifest] {
        let records=library.performances(in:room.id)
        return newestFirst ? records : records.sorted {$0.name.localizedStandardCompare($1.name) == .orderedAscending}
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Text(venue.name).font(.subheadline).foregroundStyle(.secondary)
                SpacePhotoGallery(photos:room.photos,height:150)
                HStack {Text(room.subtitle).font(.headline);Spacer();Text(room.kind.label).font(.caption).foregroundStyle(.secondary)}
                baseSection
                HStack {
                    Text("내 공연").font(.title2.bold());Spacer()
                    Menu {Picker("공연 정렬",selection:$newestFirst) {Text("최근 저장순").tag(true);Text("이름순").tag(false)}} label:{Label(newestFirst ? "최근 저장순" : "이름순",systemImage:"chevron.down").font(.caption).frame(minHeight:44)}
                }
                if performances.isEmpty {
                    VStack(spacing:10) {
                        Image(systemName:"point.topleft.down.to.point.bottomright.curvepath").font(.largeTitle)
                        Text("이 공간의 첫 공연을 준비해보세요").font(.headline)
                        Text("공연마다 무대 범위와 동선, 추가 기물을 따로 저장합니다.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth:.infinity).padding(24).background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:20))
                }
                ForEach(performances,id:\.id) {record in
                    VStack(spacing:12) {
                        StageRow(record:record,library:library,onRename:{rename=record.name;renameID=record.id})
                        HStack {
                            Button {guidanceStage=record;library.visitRoom(room.id)} label:{Label("안내 사용",systemImage:"figure.walk").frame(maxWidth:.infinity,minHeight:44)}
                            NavigationLink {PerformanceRecordsView(stage:record,library:library)} label:{Label("기록 \(library.guidanceRecords.filter {$0.stageID==record.id}.count)개",systemImage:"clock").frame(maxWidth:.infinity,minHeight:44)}
                        }.font(.subheadline)
                    }
                }
                Button {connecting=true} label:{Label("기존 저장 무대 연결",systemImage:"link").frame(maxWidth:.infinity,minHeight:44)}
                #if DEBUG
                if operatorTools {
                    Button {prepareBase()} label:{Label("기본 공간 새 버전 등록 · 운영용",systemImage:"viewfinder").frame(maxWidth:.infinity,minHeight:44)}
                    Text("이 기기에 기본 공간을 등록합니다. 공개 배포나 다른 기기로 공유하지 않습니다.").font(.caption).foregroundStyle(.secondary)
                }
                #endif
            }.padding(20)
        }.navigationTitle(room.name).navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge:.bottom) {
                Button {
                    if library.bases(in:room.id).isEmpty {prepare(base:nil)} else {choosingPreparation=true}
                } label: {
                    Label("이 공간으로 새 공연 준비",systemImage:"plus")
                        .font(.system(size:15,weight:.semibold)).frame(maxWidth:.infinity,minHeight:48)
                        .foregroundStyle(.white).background(Color.hearInk,in:RoundedRectangle(cornerRadius:13))
                }.buttonStyle(.plain).padding(.horizontal,20).padding(.vertical,10)
                    .frame(maxWidth:.infinity).background(.regularMaterial)
            }
            .task {await library.refreshGuidanceRecords()}
            .confirmationDialog("새 공연을 어떻게 준비할까요?",isPresented:$choosingPreparation,titleVisibility:.visible) {
                if let base=library.bases(in:room.id).first {Button("저장된 기본 공간 사용") {prepare(base:base)}}
                Button("공간 전체 새로 스캔") {prepare(base:nil)}
                Button("취소",role:.cancel) {}
            } message:{Text("기본 공간은 현장에서 위치를 맞춘 후 사용할 수 있어요. 기존 기본 공간과 다른 공연은 유지됩니다.")}
            .fullScreenCover(item:$request,onDismiss:{Task {await library.refresh()}}) {request in
                PreparationView(library:library,spaceRequest:request)
            }
            .fullScreenCover(isPresented:Binding(get:{guidanceStage != nil},set:{if !$0 {guidanceStage=nil}})) {
                GuidanceView(library:library,initialStage:guidanceStage)
            }
            .sheet(isPresented:$connecting) {ConnectScanSheet(venue:venue,room:room,library:library)}
            .alert("공연 이름 변경",isPresented:Binding(get:{renameID != nil},set:{if !$0 {renameID=nil}})) {
                TextField("공연 이름",text:$rename)
                Button("취소",role:.cancel) {renameID=nil}
                Button("저장") {if let id=renameID {Task {do {try await library.renameStage(id,to:rename)} catch {library.error=error.localizedDescription}}};renameID=nil}.disabled(rename.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || rename.count>80)
            }
    }
    @ViewBuilder private var baseSection: some View {
        if let base=library.bases(in:room.id).first {
            VStack(alignment:.leading,spacing:12) {
                NavigationLink {SavedStagePreview(record:base,store:library.scans)} label:{HStack {Label("기본 공간 3D로 보기",systemImage:"cube");Spacer();Image(systemName:"chevron.right")}.frame(minHeight:44)}
                Text("이 기기에 저장된 기본 공간 · \(base.date.formatted(.dateTime.locale(Locale(identifier:"ko_KR")).year().month().day()))").font(.caption).foregroundStyle(Color.hearGreen)
                if let note=base.space?.checkpointNote {
                    DisclosureGroup("위치 맞추기 기준") {Text(note).font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)}.font(.caption)
                }
                if library.bases(in:room.id).count>1 {
                    DisclosureGroup("이전 기본 공간 버전") {
                        ForEach(library.bases(in:room.id).dropFirst(),id:\.id) {older in
                            HStack {
                                NavigationLink(older.date.formatted(.dateTime.locale(Locale(identifier:"ko_KR")).month().day().hour().minute())) {SavedStagePreview(record:older,store:library.scans)}
                                Spacer();Button("사용") {prepare(base:older)}.frame(minHeight:44)
                            }.font(.caption)
                        }
                    }
                }
            }.padding(.vertical,6).overlay(alignment:.bottom) {Divider()}
        } else {
            Label("공간 정보만 등록됨 · 첫 공연은 전체 스캔으로 준비해요",systemImage:"viewfinder").font(.subheadline).foregroundStyle(.secondary).padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:16))
        }
    }
    private func prepare(base: ScanManifest?) {
        library.visitRoom(room.id)
        request=SpacePreparationRequest(context:.init(venueID:venue.id,roomID:room.id,baseScanID:base?.id,baseMeshHash:base?.meshHash,roomArea:base?.space?.roomArea),base:base,title:"새 공연")
    }
    private func prepareBase() {
        request=SpacePreparationRequest(context:.init(venueID:venue.id,roomID:room.id,purpose:.base),base:nil,title:room.name+" 기본 공간")
    }
}

struct PerformanceRecordsView: View {
    let stage: ScanManifest
    @ObservedObject var library: StageLibrary
    var body: some View {
        List {
            if let error=library.recordError {Text(error).foregroundStyle(.red)}
            let records=library.guidanceRecords.filter {$0.stageID==stage.id}
            if records.isEmpty {Text("안내를 완료하면 이 공연의 기록이 표시됩니다.").foregroundStyle(.secondary)}
            ForEach(records) {record in
                NavigationLink {GuidanceRecordDetail(record:record)} label:{VStack(alignment:.leading) {Text(record.completedAt,format:.dateTime.month().day().hour().minute());Text(record.activeDurationText).font(.caption).foregroundStyle(.secondary)}}
            }
        }.navigationTitle(stage.name+" 기록").navigationBarTitleDisplayMode(.inline).task {await library.refreshGuidanceRecords()}
    }
}

struct ConnectScanSheet: View {
    let venue: SpaceVenue
    let room: VenueRoom
    @ObservedObject var library: StageLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var saving=false
    var body: some View {
        NavigationStack {
            List {
                Section {Text("실제로 ‘\(room.name)’에서 스캔한 무대를 선택해주세요. 동선과 사진은 그대로 유지됩니다.").font(.subheadline)}
                ForEach(library.unassignedScans.filter {$0.route != nil},id:\.id) {record in
                    Button {saving=true;Task {await library.assignScan(record.id,venue:venue,room:room);saving=false;if library.records.first(where:{$0.id==record.id})?.space?.roomID==room.id {dismiss()}}} label:{VStack(alignment:.leading) {Text(record.name);Text(record.date,style:.date).font(.caption).foregroundStyle(.secondary)}}.disabled(saving)
                }
                if library.unassignedScans.filter({$0.route != nil}).isEmpty {Text("연결할 저장 무대가 없어요.").foregroundStyle(.secondary)}
            }.navigationTitle("기존 무대 연결").navigationBarTitleDisplayMode(.inline).toolbar {ToolbarItem(placement:.cancellationAction) {Button("닫기") {dismiss()}.disabled(saving)}}
        }
    }
}

struct UnassignedSpacesView: View {
    @ObservedObject var library: StageLibrary
    var body: some View {
        List {
            Section {Text("장소의 내부 공간에서 ‘기존 저장 무대 연결’을 선택하면 정리할 수 있어요.").font(.subheadline)}
            ForEach(library.unassignedScans,id:\.id) {record in NavigationLink(record.name) {SavedStagePreview(record:record,store:library.scans)}}
        }.navigationTitle("장소 미연결 무대").navigationBarTitleDisplayMode(.inline)
    }
}
