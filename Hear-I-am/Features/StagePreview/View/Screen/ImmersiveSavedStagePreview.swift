import SwiftUI
import HearIAmCore

/// A saved scene fills the space folder. Every marker, photo and path comes from its scan.
struct ImmersiveSavedStagePreview: View {
    @StateObject private var model: SavedStagePreviewModel
    let scanSelector: AnyView?
    let onNewScan: (() -> Void)?
    let onStartGuidance: ((UUID) -> Void)?
    let onRename: (() -> Void)?
    let onDelete: (() -> Void)?
    @State private var gallery = false
    @State private var pointSettings = false
    @State private var closedPhotoID: UUID?

    init(record: ScanManifest, store: ScanStore, scanSelector: AnyView? = nil,
         onNewScan: (() -> Void)? = nil, onStartGuidance: ((UUID) -> Void)? = nil,
         onRename: (() -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        let model=SavedStagePreviewModel(record:record,store:store)
        model.display = .clean;model.immersive=true;model.showCleanPhotoPins=true
        model.selection = record.route?.points.isEmpty == false ? .point(0) : nil
        _model=StateObject(wrappedValue:model)
        _closedPhotoID=State(initialValue:record.photos.first {$0.routePointIndex==0}?.id)
        self.scanSelector=scanSelector;self.onNewScan=onNewScan;self.onStartGuidance=onStartGuidance
        self.onRename=onRename;self.onDelete=onDelete
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                HearV3.canvas
                if let scan=model.loaded {
                    SavedMeshView(scan:scan,model:model)
                        .accessibilityLabel("저장된 무대. 한 손가락으로 회전하고 두 손가락으로 이동하거나 확대할 수 있어요.")
                    LinearGradient(colors:[.black.opacity(0.25),.clear,.clear,.black.opacity(0.45)],startPoint:.top,endPoint:.bottom)
                        .allowsHitTesting(false)
                    if model.photoPinsVisible,let photo=model.selectedPhoto,closedPhotoID != photo.id,let anchor=model.photoAnchor {
                        photoPreview(photo,scan:scan)
                            .position(x:min(max(anchor.x*geometry.size.width,86),geometry.size.width-86),
                                      y:min(max(anchor.y*(geometry.size.height+geometry.safeAreaInsets.top+geometry.safeAreaInsets.bottom)-geometry.safeAreaInsets.top,80),geometry.size.height-180))
                    }
                } else if let error=model.error {
                    ContentUnavailableView {
                        Label("공간을 열 수 없어요",systemImage:"exclamationmark.triangle")
                    } description: {Text(error)} actions: {
                        Button("다시 시도") {Task {await model.load()}}
                    }
                } else {ProgressView("공간을 불러오는 중이에요")}
            }.ignoresSafeArea()
                .overlay(alignment:.bottom) { if model.loaded != nil { bottomControls(width:geometry.size.width-48).padding(.horizontal,24).padding(.bottom,8) } }
        }
        .background(HearV3.canvas).foregroundStyle(HearV3.text).tint(HearV3.text)
        .preferredColorScheme(.dark)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden,for:.navigationBar)
        .toolbar(.hidden,for:.tabBar)
        .toolbar {
            ToolbarItem(placement:.principal) {
                if let scanSelector {scanSelector}
                else {Label(model.record.name,systemImage:"movieclapper").labelStyle(.titleAndIcon).font(.caption.weight(.semibold)).lineLimit(1)}
            }
            ToolbarItem(placement:.topBarTrailing) {
                Menu {
                    if let onStartGuidance {
                        Button("안내 시작",systemImage:"arrow.up.right") {onStartGuidance(model.record.id)}
                            .disabled(!model.record.supportsAlignment || model.loaded?.manifest.route == nil)
                    }
                    Button("지점 방향·대기 시간",systemImage:"timer") {openPointSettings()}
                        .disabled(model.loaded?.manifest.route?.points.isEmpty != false)
                    Button("시점 초기화",systemImage:"arrow.counterclockwise") {model.setCamera(.overview)}
                    Button("동선을 위에서 보기",systemImage:"square.3.layers.3d.down.right") {model.setCamera(.overhead)}
                    Toggle("사진 위치 표시",isOn:Binding(get:{model.photoPinsVisible},set:{model.photoPinsVisible=$0}))
                    if let onNewScan {Button("새 장면 스캔",systemImage:"viewfinder",action:onNewScan)}
                    if let onRename {Button("장면 이름 변경",systemImage:"pencil",action:onRename)}
                    if let onDelete {Button("스캔 파일 삭제",systemImage:"trash",role:.destructive,action:onDelete)}
                } label: {Image(systemName:"ellipsis")}
                    .accessibilityLabel("무대 메뉴")
            }
        }
        .task {
            await model.load()
            #if DEBUG
            let args=ProcessInfo.processInfo.arguments
            if args.contains("--replay-photo"),let photo=model.loaded?.manifest.photos.first {model.select(.photo(photo.id))}
            if args.contains("--replay-middle") {model.select(.point(1))}
            if args.contains("--replay-gallery") {gallery=true}
            if args.contains("--replay-settings") {openPointSettings()}
            #endif
        }
        .onChange(of:model.selectionRevision) {_,_ in closedPhotoID=nil}
        .sheet(isPresented:$gallery) {photoGallery.suspendsVoiceWake()}
        .sheet(isPresented:$pointSettings) {pointSettingsSheet.suspendsVoiceWake()}
        .sheet(isPresented:$model.photoExpanded) {
            if let scan=model.loaded,let photo=model.selectedPhoto {
                SavedPhotoViewpoint(scan:scan,photo:photo,store:model.store,cleanSurfaces:model.cleanSurfaces,display:.clean)
                    .suspendsVoiceWake()
            }
        }
    }

    private func bottomControls(width: CGFloat) -> some View {
        VStack(alignment:.leading,spacing:10) {
            if let route=model.loaded?.manifest.route,!route.points.isEmpty {
                Button {openPointSettings()} label: {
                    Text(route.pointLabel(at:model.activePointIndex)).font(.caption.weight(.semibold))
                        .padding(.horizontal,14).padding(.vertical,5)
                }.buttonStyle(.plain).background(.thinMaterial,in:Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.20),lineWidth:0.5))
                    .offset(x:CGFloat(model.activePointIndex)/CGFloat(max(route.points.count-1,1))*max(width-58,0))
                    .accessibilityHint("바라볼 방향과 도착 후 대기 시간을 설정합니다.")
                ScrollViewReader { proxy in
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack(spacing:0) {
                            ForEach(route.points.indices,id:\.self) {index in
                                Button {model.select(.point(index))} label: {
                                    Group {
                                        if index==0 {Image(systemName:"mappin").font(.body)}
                                        else if index==route.points.count-1 {Image(systemName:"flag.pattern.checkered").font(.body)}
                                        else {Circle().fill(index==model.activePointIndex ? .white : .white.opacity(0.40)).frame(width:index==model.activePointIndex ? 12 : 7,height:index==model.activePointIndex ? 12 : 7)}
                                    }.frame(width:max(40,(width-6)/CGFloat(route.points.count)),height:44)
                                        .foregroundStyle(index==model.activePointIndex ? .white : .white.opacity(0.4))
                                        .background(index==model.activePointIndex && (index==0 || index==route.points.count-1) ? .white.opacity(0.16) : .clear,in:Circle())
                                }.buttonStyle(.plain).id(index)
                                    .accessibilityLabel(route.pointLabel(at:index))
                                    .accessibilityValue(index==model.activePointIndex ? "선택됨" : "")
                            }
                        }.padding(3)
                    }.background(.ultraThinMaterial,in:Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.25),lineWidth:0.5))
                        .onChange(of:model.activePointIndex) {_,index in withAnimation {proxy.scrollTo(index,anchor:.center)}}
                }
            }
            HStack {
                Button {gallery=true} label: {Image(systemName:"photo.on.rectangle")}
                    .accessibilityLabel("저장된 현장 사진")
                Spacer()
                if let route=model.loaded?.manifest.route,!route.points.isEmpty {
                    Button {model.select(.point(max(model.activePointIndex-1,0)))} label: {Image(systemName:"chevron.left")}
                        .disabled(model.activePointIndex==0).accessibilityLabel("이전 지점")
                    Button {model.select(.point(min(model.activePointIndex+1,route.points.count-1)))} label: {Image(systemName:"chevron.right")}
                        .disabled(model.activePointIndex>=route.points.count-1).accessibilityLabel("다음 지점")
                }
                Spacer()
                Button {openPointSettings()} label: {Image(systemName:"timer")}
                    .disabled(model.loaded?.manifest.route?.points.isEmpty != false)
                    .accessibilityLabel("선택 지점 방향과 대기 시간")
            }.buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.large)
        }
    }

    private func photoPreview(_ photo: ScanPhoto,scan: LoadedScan) -> some View {
        Button {model.photoExpanded=true} label: {
            SavedPhotoImage(store:model.store,scanID:scan.manifest.id,photo:photo,fill:true)
                .frame(width:136,height:98).clipShape(RoundedRectangle(cornerRadius:20))
                .padding(5).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:24))
                .overlay(RoundedRectangle(cornerRadius:24).stroke(.white.opacity(0.45),lineWidth:0.5))
        }.buttonStyle(.plain).accessibilityLabel("선택한 현장 사진 크게 보기")
            .overlay(alignment:.topTrailing) {
                Button {closedPhotoID=photo.id} label: {Image(systemName:"xmark").font(.caption)}
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
                    .offset(x:10,y:-10).accessibilityLabel("사진 미리보기 닫기")
            }
    }

    private var photoGallery: some View {
        NavigationStack {
            ScrollView {
                if let scan=model.loaded,!scan.manifest.photos.isEmpty {
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:105),spacing:4)],spacing:4) {
                        ForEach(scan.manifest.photos) {photo in
                            Button {gallery=false;model.select(.photo(photo.id))} label: {
                                SavedPhotoImage(store:model.store,scanID:scan.manifest.id,photo:photo,fill:true)
                                    .frame(height:100).frame(maxWidth:.infinity)
                                    .clipShape(RoundedRectangle(cornerRadius:12))
                            }.buttonStyle(.plain)
                                .accessibilityLabel("사진 \((scan.manifest.photos.firstIndex(of:photo) ?? 0)+1) 촬영 위치 보기")
                        }
                    }.padding(.horizontal,16).padding(.top,20)
                } else {ContentUnavailableView("저장된 사진이 없어요",systemImage:"photo.on.rectangle")}
            }.navigationTitle("현장 사진").navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.confirmationAction) {Button("닫기",systemImage:"xmark") {gallery=false}}}
                .background(HearV3.canvas.opacity(0.55))
        }.tint(HearV3.text).presentationDetents([.large]).presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial).preferredColorScheme(.dark)
    }

    private func openPointSettings() {
        guard let route=model.loaded?.manifest.route,!route.points.isEmpty else {return}
        model.select(.point(min(model.activePointIndex,route.points.count-1)))
        pointSettings=true
    }
    private var pointSettingsSheet: some View {
        NavigationStack {
            Form {
                Section("도착 후 바라볼 방향") {
                    Picker("방향",selection:$model.pointFacing) {
                        Text("지정 안 함").tag(StageFacing?.none)
                        ForEach(StageFacing.allCases,id:\.self) {Text($0.label).tag(Optional($0))}
                    }
                    Text("무대 앞을 북쪽으로, 앞을 바라봤을 때 오른쪽을 동쪽으로 정해요.").font(.footnote).foregroundStyle(.secondary)
                }
                if model.canEditPointHold {
                    Section("도착 후 다음 지점 안내 대기") {
                        HStack {
                            TextField("0",text:$model.holdSecondsText).keyboardType(.numberPad)
                                .accessibilityLabel("도착 후 안내 대기 시간")
                            Text("초").foregroundStyle(.secondary)
                        }
                        Text("0초는 바로 안내 · 최대 3600초. 설정한 방향을 맞춘 뒤 기다려요.").font(.footnote).foregroundStyle(.secondary)
                        if model.enteredHoldSeconds==nil {Text("0~3600 사이의 정수를 입력해주세요.").font(.footnote).foregroundStyle(.red)}
                    }
                }
                if let error=model.holdSaveError {Text(error).foregroundStyle(.red)}
                if model.savingHold {ProgressView("저장 중…")}
            }.disabled(model.savingHold)
                .navigationTitle(model.selectionTitle).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) {Button("닫기",systemImage:"xmark") {pointSettings=false}.disabled(model.savingHold)}
                    ToolbarItem(placement:.confirmationAction) {
                        Button("저장",systemImage:"checkmark") {
                            Task {await model.savePointSettings();if model.holdSaveError==nil {pointSettings=false}}
                        }.disabled(model.savingHold || model.enteredHoldSeconds==nil)
                    }
                }
        }.tint(HearV3.text).presentationDetents([.medium,.large]).presentationDragIndicator(.visible).preferredColorScheme(.dark)
    }
}
