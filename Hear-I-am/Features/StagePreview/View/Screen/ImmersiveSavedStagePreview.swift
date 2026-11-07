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
    @State private var galleryDetent=PresentationDetent.height(190)
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
        .toolbar(.hidden,for:.tabBar)
        // Figma 971:33671: back, the scene picker and ⋯ in the shared top row.
        .hearTopBar(center:{
            if let scanSelector {scanSelector}
            else {Label(model.record.name,systemImage:"movieclapper").labelStyle(.titleAndIcon).font(.caption.weight(.semibold)).lineLimit(1)}
        }) {HearBackButton()} trailing: {moreMenu}
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

    /// 971:34557: photo pins, the two camera views and rename, then deleting this scan. Starting guidance, the
    /// point settings and a new scan are not in the design but stay, in their own section.
    private var moreMenu: some View {
        Menu {
            Toggle(isOn:Binding(get:{model.photoPinsVisible},set:{model.photoPinsVisible=$0})) {
                Label("사진 위치 표시",systemImage:"photo.badge.magnifyingglass")
            }
            Section {
                Button("시점 초기화",systemImage:"arrow.counterclockwise") {model.setCamera(.overview)}
                Button("동선 위에서 보기",systemImage:"eye") {model.setCamera(.overhead)}
                if let onRename {Button("장면 이름 변경",systemImage:"pencil",action:onRename)}
            }
            Section {
                if let onStartGuidance {
                    Button("안내 시작",systemImage:"arrow.up.right") {onStartGuidance(model.record.id)}
                        .disabled(!model.record.supportsAlignment || model.loaded?.manifest.route == nil)
                }
                Button("지점 설정",systemImage:"timer") {openPointSettings()}
                    .disabled(model.loaded?.manifest.route?.points.isEmpty != false)
                if let onNewScan {Button("새 장면 스캔",systemImage:"viewfinder",action:onNewScan)}
            }
            if let onDelete {
                Section {Button("현재 스캔 파일 삭제",systemImage:"trash",role:.destructive,action:onDelete)}
            }
        } label: {HearTopButtonLabel(systemImage:"ellipsis")}
            .buttonStyle(.plain).accessibilityLabel("무대 메뉴")
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
            // 971:34370: the photos and the point settings as 48pt glass circles, the two 36pt arrows between.
            HStack {
                ScanCircleButton(systemImage:"photo.on.rectangle",label:"저장된 현장 사진",size:48) {gallery=true}
                Spacer()
                if let route=model.loaded?.manifest.route,!route.points.isEmpty {
                    HStack(spacing:12) {
                        ScanCircleButton(systemImage:"chevron.left",label:"이전 지점",size:36,enabled:model.activePointIndex>0) {
                            model.select(.point(max(model.activePointIndex-1,0)))
                        }
                        ScanCircleButton(systemImage:"chevron.right",label:"다음 지점",size:36,enabled:model.activePointIndex<route.points.count-1) {
                            model.select(.point(min(model.activePointIndex+1,route.points.count-1)))
                        }
                    }
                }
                Spacer()
                ScanCircleButton(systemImage:"timer",label:"선택 지점 설정",size:48,enabled:model.loaded?.manifest.route?.points.isEmpty == false) {
                    openPointSettings()
                }
            }
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

    /// 971:34288: a low sheet, 「현장사진」 and one row of photos; pulled up, 「전체 이미지」 in three columns (971:34319).
    private var photoGallery: some View {
        let full=galleryDetent == .large
        return VStack(alignment:.leading,spacing:14) {
            HStack {
                Text(full ? "전체 이미지" : "현장사진").font(HearFont.pretendard(.semibold,size:22)).foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if full {ScanCircleButton(systemImage:"xmark",label:"닫기") {gallery=false}}
            }.frame(height:44)
            if let scan=model.loaded,!scan.manifest.photos.isEmpty {
                if full {
                    ScrollView {
                        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:3),spacing:8) {
                            ForEach(scan.manifest.photos) {photo in galleryTile(photo,scan:scan).aspectRatio(1.36,contentMode:.fit)}
                        }
                    }.scrollIndicators(.hidden)
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing:8) {
                            ForEach(scan.manifest.photos) {photo in galleryTile(photo,scan:scan).frame(width:110,height:84)}
                        }
                    }.scrollIndicators(.hidden).frame(height:84)
                }
            } else {
                Text("저장된 사진이 없어요").font(.subheadline).foregroundStyle(HearV3.secondary)
            }
            Spacer(minLength:0)
        }.padding(.horizontal,20).padding(.top,full ? 20 : 14)
            .presentationDetents([.height(190),.large],selection:$galleryDetent).presentationDragIndicator(.visible)
            .presentationCornerRadius(42).presentationBackground {HearSheetBackground()}.presentationBackgroundInteraction(.enabled(upThrough:.height(190)))
            .preferredColorScheme(.dark)
    }
    private func galleryTile(_ photo: ScanPhoto,scan: LoadedScan) -> some View {
        Button {gallery=false;model.select(.photo(photo.id))} label: {
            Color.clear.overlay {SavedPhotoImage(store:model.store,scanID:scan.manifest.id,photo:photo,fill:true)}
                .clipShape(RoundedRectangle(cornerRadius:6,style:.continuous))
        }.buttonStyle(.plain)
            .accessibilityLabel("사진 \((scan.manifest.photos.firstIndex(of:photo) ?? 0)+1) 촬영 위치 보기")
    }

    private func openPointSettings() {
        guard let route=model.loaded?.manifest.route,!route.points.isEmpty else {return}
        model.select(.point(min(model.activePointIndex,route.points.count-1)))
        pointSettings=true
    }
    /// 971:33834: 「n번 지점 설정」, a switch for waiting before the next move, 5 · 10 · 20 s and − value + , then
    /// 「지점 설정 저장」. The facing direction is not in the design but stays as one row under it.
    private var pointSettingsSheet: some View {
        let seconds=model.enteredHoldSeconds ?? 0
        let waits=Binding(get:{seconds>0},set:{model.holdSecondsText=$0 ? "10" : "0"})
        return VStack(alignment:.leading,spacing:0) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:4) {
                    Text("\(model.activePointIndex+1)번 지점 설정").font(HearFont.pretendard(.semibold,size:22)).foregroundStyle(.white)
                    Text(model.selectionTitle).font(HearFont.pretendard(.regular,size:14)).foregroundStyle(HearV3.secondary)
                }
                Spacer()
                ScanCircleButton(systemImage:"xmark",label:"닫기",enabled:!model.savingHold) {pointSettings=false}
            }
            if model.canEditPointHold {
                Toggle(isOn:waits) {
                    Text("다음 이동 전 대기").font(HearFont.pretendard(.regular,size:15)).foregroundStyle(.white)
                }.tint(.white).padding(.top,14)
                if seconds>0 {
                    HStack(spacing:8) {
                        ForEach([5,10,20],id:\.self) {value in
                            Button {model.holdSecondsText=String(value)} label: {
                                Text("\(value)초").font(HearFont.pretendard(.medium,size:15))
                                    .foregroundStyle(seconds==value ? .black : .white)
                                    .padding(.horizontal,14).frame(height:32)
                                    .background(seconds==value ? Color.white : Color.white.opacity(0.1),in:Capsule())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.top,16)
                    HStack {
                        ScanCircleButton(systemImage:"minus",label:"5초 줄이기",size:48,enabled:seconds>5) {model.holdSecondsText=String(max(seconds-5,5))}
                        Spacer()
                        Text("\(seconds)초").font(HearFont.pretendard(.semibold,size:28)).foregroundStyle(.white).monospacedDigit()
                        Spacer()
                        ScanCircleButton(systemImage:"plus",label:"5초 늘리기",size:48,enabled:seconds<3600) {model.holdSecondsText=String(min(seconds+5,3600))}
                    }.padding(.top,20)
                }
            }
            HStack {
                Text("도착 후 바라볼 방향").font(HearFont.pretendard(.regular,size:15)).foregroundStyle(.white)
                Spacer()
                Picker("방향",selection:$model.pointFacing) {
                    Text("지정 안 함").tag(StageFacing?.none)
                    ForEach(StageFacing.allCases,id:\.self) {Text($0.label).tag(Optional($0))}
                }.tint(HearV3.secondary)
            }.padding(.top,18)
            if let error=model.holdSaveError {Text(error).font(.footnote).foregroundStyle(.red).padding(.top,8)}
            Spacer(minLength:16)
            Button {
                Task {await model.savePointSettings();if model.holdSaveError==nil {pointSettings=false}}
            } label: {
                Group {if model.savingHold {ProgressView()} else {Text("지점 설정 저장")}}
                    .font(HearFont.pretendard(.semibold,size:17)).foregroundStyle(.black)
                    .frame(maxWidth:.infinity).frame(height:50).background(.white,in:Capsule())
            }.buttonStyle(.plain).disabled(model.savingHold || model.enteredHoldSeconds==nil)
        }.padding(.horizontal,24).padding(.top,24).padding(.bottom,12)
            .disabled(model.savingHold)
            .hearSheet([.height(model.canEditPointHold ? 400 : 240)])
    }
}
