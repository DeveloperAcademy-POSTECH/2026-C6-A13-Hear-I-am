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
    @State private var galleryDetent=PresentationDetent.height(200)
    @State private var pointSettings = false
    @State private var closedPhotoID: UUID?
    /// The route bar: a small capsule at first (971:33671), opened into the full-width bar (971:34370).
    @State private var barExpanded = false
    /// Where an open sheet's top edge is on screen, so the opened bar can ride up on it (971:33834 · 971:34288).
    @State private var sheetTop: CGFloat?
    @Namespace private var barSpace

    init(record: ScanManifest, store: ScanStore, scanSelector: AnyView? = nil,
         onNewScan: (() -> Void)? = nil, onStartGuidance: ((UUID) -> Void)? = nil,
         onRename: (() -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        let model=SavedStagePreviewModel(record:record,store:store)
        model.display = .clean;model.immersive=true;model.showCleanPhotoPins=true
        model.selection = record.route?.points.isEmpty == false ? .point(0) : nil
        _model=StateObject(wrappedValue:model)
        self.scanSelector=scanSelector;self.onNewScan=onNewScan;self.onStartGuidance=onStartGuidance
        self.onRename=onRename;self.onDelete=onDelete
    }

    var body: some View {
        GeometryReader { geometry in
            let safeBottom=geometry.safeAreaInsets.bottom
            let screenBottom=geometry.frame(in:.global).maxY+safeBottom
            ZStack {
                HearV3.canvas
                if let scan=model.loaded {
                    SavedMeshView(scan:scan,model:model)
                        .accessibilityLabel("저장된 무대. 한 손가락으로 회전하고 두 손가락으로 이동하거나 확대할 수 있어요.")
                        .simultaneousGesture(TapGesture().onEnded {
                            if barExpanded && !pointSettings && !gallery {withAnimation(Self.barSpring) {barExpanded=false}}
                        })
                    LinearGradient(colors:[.black.opacity(0.25),.clear,.clear,.black.opacity(0.45)],startPoint:.top,endPoint:.bottom)
                        .allowsHitTesting(false)
                    if let photo=shownPhoto,let anchor=model.photoAnchor {
                        // 971:33671: with the bar closed, the stage dims behind the point's photo.
                        Color.black.opacity(barExpanded ? 0 : 0.6).allowsHitTesting(false)
                        photoPreview(photo,scan:scan)
                            .position(x:min(max(anchor.x*geometry.size.width,86),geometry.size.width-86),
                                      y:min(max(anchor.y*(geometry.size.height+geometry.safeAreaInsets.top+safeBottom)-geometry.safeAreaInsets.top,80),geometry.size.height-200))
                            .transition(.opacity.combined(with:.scale(scale:0.92)))
                    }
                    if let route=scan.manifest.route,!route.points.isEmpty {
                        controls(route:route,safeBottom:safeBottom,screenBottom:screenBottom,width:geometry.size.width)
                    } else {
                        HStack {
                            ScanCircleButton(systemImage:"photo.on.rectangle",label:"저장된 현장 사진",size:48) {gallery=true}
                            Spacer()
                        }.padding(.horizontal,27).padding(.bottom,safeBottom).frame(maxHeight:.infinity,alignment:.bottom)
                    }
                } else if let error=model.error {
                    ContentUnavailableView {
                        Label("공간을 열 수 없어요",systemImage:"exclamationmark.triangle")
                    } description: {Text(error)} actions: {
                        Button("다시 시도") {Task {await model.load()}}
                    }
                } else {ProgressView("공간을 불러오는 중이에요")}
            }.ignoresSafeArea()
                .animation(.easeInOut(duration:0.2),value:shownPhoto?.id)
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
            if let i=args.firstIndex(of:"--replay-point"),args.indices.contains(i+1),let n=Int(args[i+1]) {model.select(.point(n))}
            if args.contains("--replay-expanded") {barExpanded=true}
            if args.contains("--replay-gallery") {barExpanded=true;gallery=true}
            if args.contains("--replay-settings") {barExpanded=true;openPointSettings()}
            #endif
        }
        .onChange(of:model.selectionRevision) {_,_ in closedPhotoID=nil}
        .onChange(of:gallery || pointSettings) {_,open in if !open {withAnimation(Self.barSpring) {sheetTop=nil}}}
        .sheet(isPresented:$gallery) {photoGallery.background(SheetTopReporter {top in withAnimation(Self.barSpring) {sheetTop=top}}).suspendsVoiceWake()}
        .sheet(isPresented:$pointSettings) {pointSettingsSheet.background(SheetTopReporter {top in withAnimation(Self.barSpring) {sheetTop=top}}).suspendsVoiceWake()}
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

    static let barSpring=Animation.spring(duration:0.42,bounce:0.18)
    private static let grey=Color(red:118/255,green:118/255,blue:118/255)
    /// The point's photo, unless it was closed. Shown while photo pins are on.
    private var shownPhoto: ScanPhoto? {
        guard model.photoPinsVisible,let photo=model.selectedPhoto,closedPhotoID != photo.id else {return nil}
        return photo
    }

    /// The bottom of the stage: photos and point settings at the corners, the route between them. Closed, the route
    /// is a 94pt capsule between the arrows; opened, it is a full-width bar above them that you drag along like a
    /// video's timeline. While a sheet is up the opened bar rides on its top edge.
    private func controls(route: StageRoute,safeBottom: CGFloat,screenBottom: CGFloat,width: CGFloat) -> some View {
        let count=route.points.count, index=min(model.activePointIndex,count-1)
        let resting=safeBottom+48+12
        let lifted=sheetTop.map {screenBottom-$0+16}
        let hideBar=(lifted ?? 0)>screenBottom*0.6
        return ZStack(alignment:.bottom) {
            HStack(spacing:0) {
                ScanCircleButton(systemImage:"photo.on.rectangle",label:"저장된 현장 사진",size:48) {
                    withAnimation(Self.barSpring) {barExpanded=true};gallery=true
                }
                Spacer(minLength:8)
                HStack(spacing:barExpanded ? 12 : 6) {
                    arrow("chevron.left",label:"이전 지점",enabled:index>0) {model.select(.point(index-1))}
                    if !barExpanded {
                        collapsedRoute(route:route,index:index)
                            .overlay(alignment:.top) {pointChip(route.pointLabel(at:index)).offset(y:-38)}
                    }
                    arrow("chevron.right",label:"다음 지점",enabled:index<count-1) {model.select(.point(index+1))}
                }
                Spacer(minLength:8)
                ScanCircleButton(systemImage:"timer",label:"선택 지점 설정",size:48) {
                    withAnimation(Self.barSpring) {barExpanded=true};openPointSettings()
                }
            }.padding(.horizontal,27).padding(.bottom,safeBottom)
            if barExpanded && !hideBar {
                expandedRoute(route:route,index:index,width:width-56)
                    .padding(.bottom,lifted ?? resting)
                    .transition(.opacity)
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.bottom)
            .sensoryFeedback(.selection,trigger:model.activePointIndex)
    }
    private func arrow(_ symbol: String,label: String,enabled: Bool,action: @escaping () -> Void) -> some View {
        Button(action:action) {
            Image(systemName:symbol).font(.system(size:12,weight:.semibold)).foregroundStyle(enabled ? Color(white:0.98) : Self.grey)
                .frame(width:36,height:36).liquidGlass(Circle(),tint:.white.opacity(0.05),interactive:true).contentShape(Circle())
        }.buttonStyle(.plain).disabled(!enabled).accessibilityLabel(label)
    }
    private func pointChip(_ text: String) -> some View {
        Text(text).font(.system(size:14,weight:.semibold)).foregroundStyle(.white).lineLimit(1)
            .padding(.horizontal,12).frame(height:28).background(.white.opacity(0.1),in:Capsule())
            .allowsHitTesting(false)
    }
    /// 971:33671: a window onto the route, the selected point kept in view. Tapping opens the bar.
    private func collapsedRoute(route: StageRoute,index: Int) -> some View {
        let count=route.points.count
        let widths=(0..<count).map {$0==0 || $0==count-1 ? CGFloat(28) : CGFloat(20)}
        let total=widths.reduce(0,+)
        let center=widths.prefix(index).reduce(0,+)+widths[index]/2
        let offset=total<=72 ? (94-total)/2 : min(11,max(94-11-total,47-center))
        return ZStack(alignment:.leading) {
            Capsule().fill(.clear).liquidGlass(Capsule(),tint:.white.opacity(0.05),interactive:true)
                .matchedGeometryEffect(id:"bar",in:barSpace)
            HStack(spacing:0) {
                ForEach(0..<count,id:\.self) {i in routeItem(i,count:count,selected:i==index,end:28,dot:5,picked:9).frame(width:widths[i])}
            }.offset(x:offset)
        }.frame(width:94,height:44).clipShape(Capsule()).contentShape(Capsule())
            .onTapGesture {withAnimation(Self.barSpring) {barExpanded=true}}
            .accessibilityElement(children:.ignore).accessibilityAddTraits(.isButton)
            .accessibilityLabel("동선 \(route.pointLabel(at:index)), 펼치기")
    }
    /// 971:34370 · 971:34415: every point in a row; drag along it to move between points.
    private func expandedRoute(route: StageRoute,index: Int,width: CGFloat) -> some View {
        let count=route.points.count
        let slot=(width-14)/CGFloat(count)
        let chipX=min(max(7+slot*(CGFloat(index)+0.5)-width/2,-width/2+30),width/2-30)
        return VStack(spacing:10) {
            pointChip(route.pointLabel(at:index)).offset(x:chipX).animation(Self.barSpring,value:index)
            ZStack {
                Capsule().fill(.clear).liquidGlass(Capsule(),tint:.white.opacity(0.05),interactive:true)
                    .matchedGeometryEffect(id:"bar",in:barSpace)
                HStack(spacing:0) {
                    ForEach(0..<count,id:\.self) {i in routeItem(i,count:count,selected:i==index,end:36,dot:10,picked:16).frame(width:slot)}
                }.padding(.horizontal,7)
            }.frame(width:width,height:50).contentShape(Capsule())
                .gesture(DragGesture(minimumDistance:0).onChanged {value in
                    let i=min(max(Int((value.location.x-7)/slot),0),count-1)
                    if i != model.activePointIndex {withAnimation(Self.barSpring) {model.select(.point(i))}}
                })
                .accessibilityElement(children:.ignore).accessibilityLabel("동선")
                .accessibilityValue(route.pointLabel(at:index))
                .accessibilityAdjustableAction {direction in
                    switch direction {
                    case .increment: if index<count-1 {model.select(.point(index+1))}
                    case .decrement: if index>0 {model.select(.point(index-1))}
                    @unknown default: break
                    }
                }
        }
    }
    /// Start and arrival: a ring and a white symbol when chosen, grey otherwise. Points between: a dot that grows white.
    @ViewBuilder private func routeItem(_ i: Int,count: Int,selected: Bool,end: CGFloat,dot: CGFloat,picked: CGFloat) -> some View {
        if i==0 || i==count-1 {
            Image(systemName:i==0 ? "mappin" : "flag.pattern.checkered").font(.system(size:end*0.45,weight:.medium))
                .foregroundStyle(selected ? .white : Self.grey)
                .frame(width:end,height:end).background(Circle().fill(.white.opacity(selected ? 0.2 : 0)))
                .animation(Self.barSpring,value:selected)
        } else {
            Circle().fill(selected ? .white : .white.opacity(0.45)).frame(width:selected ? picked : dot,height:selected ? picked : dot)
                .frame(width:end,height:end).animation(Self.barSpring,value:selected)
        }
    }

    /// 971:33671: the point's photo in a 136 × 104 glass frame, a close button on its corner.
    private func photoPreview(_ photo: ScanPhoto,scan: LoadedScan) -> some View {
        Button {model.photoExpanded=true} label: {
            SavedPhotoImage(store:model.store,scanID:scan.manifest.id,photo:photo,fill:true)
                .frame(width:124,height:94).clipShape(RoundedRectangle(cornerRadius:20,style:.continuous))
                .frame(width:136,height:104)
                .liquidGlass(RoundedRectangle(cornerRadius:24,style:.continuous),tint:.white.opacity(0.05))
        }.buttonStyle(.plain).accessibilityLabel("선택한 지점 사진 크게 보기")
            .overlay(alignment:.topTrailing) {
                ScanCircleButton(systemImage:"xmark",label:"사진 미리보기 닫기",size:32) {closedPhotoID=photo.id}
                    .offset(x:12,y:-12)
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
            .presentationDetents([.height(200),.large],selection:$galleryDetent).presentationDragIndicator(.visible)
            .presentationCornerRadius(42).presentationBackground {HearSheetBackground()}.presentationBackgroundInteraction(.enabled(upThrough:.height(200)))
            .preferredColorScheme(.dark)
    }
    private func galleryTile(_ photo: ScanPhoto,scan: LoadedScan) -> some View {
        Button {gallery=false;model.select(.photo(photo.id))} label: {
            Color.clear.overlay {SavedPhotoImage(store:model.store,scanID:scan.manifest.id,photo:photo,fill:true)}
                .clipShape(RoundedRectangle(cornerRadius:6,style:.continuous))
        }.buttonStyle(.plain)
            .accessibilityLabel("사진 \((scan.manifest.photos.firstIndex(of:photo) ?? 0)+1) 촬영 위치 보기")
    }

    /// 「3번 지점 설정」 for P3; the start and the arrival by name.
    private var pointSettingsTitle: String {
        let count=model.loaded?.manifest.route?.points.count ?? 0, i=model.activePointIndex
        return i==0 ? "출발 지점 설정" : i==count-1 ? "도착 지점 설정" : "\(i)번 지점 설정"
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
                Text(pointSettingsTitle).font(HearFont.pretendard(.semibold,size:22)).foregroundStyle(.white)
                Spacer()
                ScanCircleButton(systemImage:"xmark",label:"닫기",enabled:!model.savingHold) {pointSettings=false}
            }
            if model.canEditPointHold {
                // 971:33834: the switch sits on the line under the title.
                Toggle(isOn:waits) {
                    Text("다음 이동 전 대기").font(HearFont.pretendard(.regular,size:14)).foregroundStyle(HearV3.secondary)
                }.tint(.white).padding(.top,-6)
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
            // The route bar above stays usable: dragging it moves the sheet to the next point.
            .presentationBackgroundInteraction(.enabled)
    }
}

/// Reports where a sheet's top edge is on screen, and nil when it goes.
private struct SheetTopReporter: View {
    let report: (CGFloat?) -> Void
    var body: some View {
        GeometryReader {geometry in
            Color.clear
                .onAppear {report(geometry.frame(in:.global).minY)}
                .onChange(of:geometry.frame(in:.global).minY) {_,top in report(top)}
        }.onDisappear {report(nil)}
    }
}
