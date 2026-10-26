import SwiftUI
import HearIAmCore

struct SavedStagePreview: View {
    @StateObject private var model: SavedStagePreviewModel
    init(record: ScanManifest, store: ScanStore, camera: ReplayCamera = .overview, display: ReplayDisplay = .scan, selection: ReplaySelection? = nil) {
        let model=SavedStagePreviewModel(record:record,store:store)
        model.cameraMode=camera;model.display=display;model.selection=selection
        model.photoCardCollapsed=display == .clean
        if case .photo=selection {model.photoPinsVisible=true;model.photoCardCollapsed=false}
        _model=StateObject(wrappedValue:model)
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    if let scan=model.loaded {
                        Picker("공간 표시",selection:$model.display) {
                            ForEach(ReplayDisplay.allCases,id:\.self) {Text($0.rawValue).tag($0)}
                        }.pickerStyle(.segmented)
                        ZStack(alignment:.bottomTrailing) {
                            SavedMeshView(scan:scan,model:model)
                                .accessibilityLabel("저장된 무대 3D 공간. 아래 목록에서도 지점과 기물을 선택할 수 있어요.")
                            if let photo=model.selectedPhoto {
                                VStack(alignment:.leading,spacing:4) {
                                    HStack {
                                        Button {model.photoExpanded=true} label:{
                                            Label("사진 시점 보기",systemImage:"viewfinder").font(.caption.bold())
                                        }.buttonStyle(.plain)
                                        Button {model.photoCardCollapsed.toggle()} label:{
                                            Image(systemName:model.photoCardCollapsed ? "chevron.up" : "chevron.down").font(.caption)
                                        }.accessibilityLabel(model.photoCardCollapsed ? "사진 펼치기" : "사진 접기")
                                    }
                                    if !model.photoCardCollapsed {
                                        Button {model.photoExpanded=true} label:{
                                            SavedPhotoImage(store:model.store,scanID:scan.manifest.id,photo:photo)
                                                .frame(width:140,height:85)
                                        }.buttonStyle(.plain)
                                    }
                                }.padding(8).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)).padding(10)
                            }
                        }.frame(height:max(260,min(geometry.size.height*0.55,520))).clipShape(RoundedRectangle(cornerRadius:20))
                            .overlay(alignment:.topTrailing) {
                                Button {model.setCamera(.overview)} label:{
                                    Label("시점 초기화",systemImage:"arrow.counterclockwise")
                                        .font(.caption.weight(.semibold)).padding(.horizontal,12).frame(minHeight:44)
                                        .background(.regularMaterial,in:Capsule())
                                }.buttonStyle(.plain).padding(10)
                                    .accessibilityHint("회전, 이동, 확대를 초기화하고 전체 시점으로 돌아갑니다.")
                            }
                        HStack {
                            ForEach(ReplayCamera.allCases,id:\.self) { mode in
                                Button {model.setCamera(mode)} label:{
                                    Text(mode.rawValue).font(.subheadline.weight(.semibold)).frame(maxWidth:.infinity).padding(.vertical,10)
                                        .background(model.cameraMode==mode ? Color.hearGreen : Color(.systemGray6),in:Capsule())
                                        .foregroundStyle(model.cameraMode==mode ? Color.white : Color.primary)
                                }.buttonStyle(.plain).accessibilityAddTraits(model.cameraMode==mode ? .isSelected : [])
                            }
                        }
                        if model.display == .scan {Toggle("표면 선 보기",isOn:$model.wireframe)}
                        Text("한 손가락 회전 · 두 손가락 이동 · 핀치 확대").font(.caption).foregroundStyle(.secondary)
                        if let route=scan.manifest.route {
                            ScrollView(.horizontal) {
                                HStack {
                                    ForEach(route.points.indices,id:\.self) {i in
                                        selectionButton(route.pointLabel(at:i),.point(i))
                                    }
                                }
                            }
                            if !route.obstacles.isEmpty {
                                ScrollView(.horizontal) {HStack {ForEach(route.obstacles) {o in selectionButton(o.name,.object(o.id))}}}
                            }
                            if !route.dangerZones.isEmpty {Text(StageDangerZone.summary(route.dangerZones)).font(.caption).foregroundStyle(.orange)}
                        } else {
                            Text("이 저장 공간에는 동선이 없어 스캔 표면을 표시해요.").font(.caption)
                        }
                        if !scan.manifest.photos.isEmpty {
                            Toggle("사진 촬영 위치 표시",isOn:Binding(get:{model.photoPinsVisible},set:{model.photoPinsVisible=$0}))
                            ScrollView(.horizontal) {
                                LazyHStack {
                                    ForEach(scan.manifest.photos) {photo in
                                        Button {model.select(.photo(photo.id));model.photoExpanded=true} label:{
                                            SavedPhotoImage(store:model.store,scanID:scan.manifest.id,photo:photo)
                                                .frame(width:110,height:76).background(Color(.systemGray6))
                                                .clipShape(RoundedRectangle(cornerRadius:10))
                                                .overlay(RoundedRectangle(cornerRadius:10).stroke(model.selectedPhoto?.id==photo.id ? Color.hearGreen : .clear,lineWidth:3))
                                        }.buttonStyle(.plain).accessibilityLabel("사진 \(scan.manifest.photos.firstIndex(of:photo).map {$0+1} ?? 1) 촬영 시점 보기")
                                    }
                                }.padding(3)
                            }
                            if let photo=model.selectedPhoto {
                                Text(photo.capturedAt,format:.dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                            }
                        } else {Label("저장된 현장 사진이 없어요",systemImage:"photo").font(.caption).foregroundStyle(.secondary)}
                        Text("스캔된 표면과 등록 정보를 보여줘요. 실제 사용 전에는 현장에서 공간을 확인해주세요.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if let error=model.error {
                        ContentUnavailableView("3D 공간을 열 수 없어요",systemImage:"exclamationmark.triangle",description:Text(error))
                        Button("다시 시도") {Task {await model.load()}}
                    } else {ProgressView("공간을 불러오는 중입니다…").frame(maxWidth:.infinity,minHeight:300)}
                }.padding(16)
            }
        }.navigationTitle(model.record.name).navigationBarTitleDisplayMode(.inline)
            .task {
                await model.load()
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--replay-comparison"),let photo=model.loaded?.manifest.photos.first {
                    model.select(.photo(photo.id));model.photoExpanded=true
                }
                #endif
            }
            .onChange(of:model.display) { _,display in
                if display == .clean {model.photoCardCollapsed=true}
            }
            .sheet(isPresented:$model.photoExpanded) {
                if let scan=model.loaded,let photo=model.selectedPhoto {
                    SavedPhotoViewpoint(scan:scan,photo:photo,store:model.store,cleanSurfaces:model.cleanSurfaces,display:model.display)
                }
            }
    }

    private func selectionButton(_ text: String,_ value: ReplaySelection) -> some View {
        Button {model.select(value)} label:{
            Text(text).font(.subheadline).padding(.horizontal,14).padding(.vertical,10)
                .background(model.selection==value ? Color.hearGreen.opacity(0.15) : Color(.systemGray6),in:Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(model.selection==value ? .isSelected : [])
    }
}
