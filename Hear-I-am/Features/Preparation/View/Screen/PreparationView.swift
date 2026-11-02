import SwiftUI
import HearIAmCore

/// Landscape stage preparation over a full-screen camera.
struct PreparationView: View {
    @ObservedObject var library: StageLibrary
    @StateObject private var model: PreparationViewModel
    private let onSaved: ((UUID) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// Black until the window has turned to landscape; black again while it turns back (see `ScanTransition`).
    @State private var veiled=true
    @State private var closing=false
    @State private var showingSettings=false
    init(library: StageLibrary, initialPlan: PerformancePlan? = nil, onSaved: ((UUID) -> Void)? = nil) {
        self.library=library
        self.onSaved=onSaved
        _model=StateObject(wrappedValue:PreparationViewModel(initialPlan:initialPlan))
    }
    var body: some View {
        GeometryReader { safe in
        let insets=safe.safeAreaInsets
        ZStack {
            CameraView(model:model.session).frame(maxWidth:.infinity,maxHeight:.infinity)
            if !model.supported {Color(white:0.12)}
            if model.supported {
                // From 무대 범위 on, where points are placed at the crosshair; 스캔하기 places none.
                if model.step >= .boundary {
                    Image(systemName:"plus").font(.system(size:34,weight:.light))
                        .foregroundStyle(!model.aimBlocked ? Color.black : .red).shadow(color:.white.opacity(0.8),radius:1.5)
                        .accessibilityHidden(true)
                }
                // Figma 452:11120: everything floats on the camera; the plan sits on the right edge.
                VStack(spacing:0) {
                    PreparationStepBar(model:model) {if model.exitNeedsConfirmation {model.confirmingExit=true} else {close()}}
                    Spacer(minLength:8)
                    ZStack(alignment:.bottom) {
                        PreparationToolGroup(model:model,hasPlans:!library.plans.isEmpty)
                        HStack(alignment:.bottom) {
                            PreparationPhotoControls(model:model)
                            Spacer()
                            PreparationControls(model:model)
                        }
                    }
                }.padding(.leading,insets.leading+16).padding(.trailing,insets.trailing+16)
                    .padding(.top,insets.top+14).padding(.bottom,insets.bottom+14)
                if model.step != .scan {
                    HStack {
                        Spacer()
                        PreparationGuideCard(model:model,maxHeight:max(160,safe.size.height-150),edgeGap:insets.trailing+8)
                    }.padding(.trailing,insets.trailing+8).padding(.top,70).padding(.bottom,80)
                }
            }
            // Nothing behind the opening coaching can be pressed until its card shows.
            if model.openingCoaching {
                Color.black.opacity(0.001).contentShape(Rectangle()).onTapGesture {}
                    .accessibilityHidden(true)
            }
            dangerZoneCard(insets:insets)
            morePanel(insets:insets)
            if let intro=model.intro, model.supported {
                Color.black.opacity(0.25)
                PreparationIntro(step:model.step.rawValue,page:intro) {model.intro=$0}.padding(16)
            }
            // The soft blue pulse over the Camera Control button (top edge, right of centre in this orientation),
            // whenever that button places a point and on the card that explains it (452:11339).
            if model.cameraControlActive || (model.step >= .objects && model.intro == 1) {
                CameraControlGlow().frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top).allowsHitTesting(false)
            }
            if model.confirmingScan {
                ScanConfirmCard(title:"공간 스캔을 확정할까요?",
                                message:"공연장과 백스테이지가 충분히 포함됐는지 확인해주세요. 확정 후에는 스캔 단계로 돌아갈 수 없습니다.",
                                cancel:"계속 스캔",confirm:"공간 확정",onCancel:{model.confirmingScan=false},onConfirm:{model.confirmingScan=false;model.confirmScan()})
            }
            if !model.supported {
                VStack(spacing:16) {
                    ContentUnavailableView("LiDAR 지원 iPhone이 필요해요",systemImage:"camera",description:Text("무대 준비는 실제 카메라와 LiDAR로 공간을 저장합니다. 시뮬레이터에서는 스캔할 수 없어요."))
                    ScanCardButton(title:"나가기",primary:false) {close()}.frame(width:160)
                }.padding(28).frame(maxWidth:500).scanCard()
            }
            if model.interrupted {
                VStack(spacing:14) {
                    Label("공간 추적이 잠시 멈췄어요",systemImage:"pause.circle").font(.headline).foregroundStyle(.white)
                    Text("입력한 정보는 유지됩니다. 같은 공간을 비추고 다시 시작해주세요.").font(.subheadline).foregroundStyle(.white.opacity(0.75))
                    ScanCardButton(title:"추적 다시 시작") {model.resumeTracking()}.frame(width:200)
                }.padding(28).scanCard()
            }
            if model.choosingPlan {
                PreparationPlanPicker(plans:library.plans,initialID:model.selectedPlan?.id,onConfirm:{model.selectReferencePlan($0)},onCancel:{model.choosingPlan=false})
            }
            if model.review {PreparationReviewCard(model:model)}
            if model.isSaving {
                Color.black.opacity(0.35)
                VStack(spacing:16) {ProgressView().tint(.white); Text("무대 정보를 저장하는 중입니다…").font(.headline).foregroundStyle(.white)}
                    .padding(32).scanCard()
            }
        }.frame(width:safe.size.width+insets.leading+insets.trailing,height:safe.size.height+insets.top+insets.bottom)
            .animation(.smooth(duration:0.35),value:model.editingDangerZones)
            .ignoresSafeArea()
        }.background(.black).preferredColorScheme(.light)
            .overlay {ScanVeil(on:veiled)}
            .sheet(isPresented:$showingSettings) {NavigationStack {HomeSettingsView(role:.helper)}}
            .sheet(isPresented:$model.showingPhotos) {PreparationPhotosSheet(model:model)}
            .onAppear {
                ScreenOrientation.set(.landscape); model.appear()
                Task { @MainActor in
                    try? await Task.sleep(for:.seconds(ScanTransition.rotation))
                    withAnimation(.easeOut(duration:ScanTransition.fade)) {veiled=false}
                }
            }
            .onDisappear {model.disappear(); ScreenOrientation.set(.portrait)}
            .onChange(of:scenePhase) {_,phase in model.scenePhaseChanged(phase)}
            .onChange(of:model.savedID) {_,id in
                guard let id else {return}
                onSaved?(id)
                close()
            }
            .alert("이 위치를 경로점으로 추가할까요?",isPresented:$model.confirmingRouteHeight) {
                Button("다시 선택",role:.cancel) {model.cancelRouteHeight()}
                Button("이 위치로 추가") {model.confirmRouteHeight()}
            } message:{Text(model.routeHeightMessage)}
            .alert("확인해주세요",isPresented:Binding(get:{model.errorMessage != nil},set:{if !$0 {model.errorMessage=nil}})) {Button("확인",role:.cancel) {model.errorMessage=nil}} message:{Text(model.errorMessage ?? "")}
            .confirmationDialog("준비를 종료할까요? 저장하지 않은 내용은 사라집니다.",isPresented:$model.confirmingExit,titleVisibility:.visible) {
                Button("저장하지 않고 나가기",role:.destructive) {close()}; Button("계속 준비",role:.cancel) {}
            }
    }
    /// Fade to black, turn the window back to portrait unseen, then drop the cover without the slide-down.
    /// The ⋯ panel opens under its button, top right; a tap anywhere else closes it (452:12878).
    @ViewBuilder private func morePanel(insets: EdgeInsets) -> some View {
        if model.showingMore {
            Color.black.opacity(0.001)
                .onTapGesture {withAnimation(.snappy(duration:0.3)) {model.showingMore=false}}
            PreparationMorePanel(model:model) {showingSettings=true}
                .padding(.top,insets.top+14+44+8).padding(.trailing,insets.trailing+16)
                .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topTrailing)
                .transition(.scale(scale:0.85,anchor:.topTrailing).combined(with:.opacity))
                .zIndex(2)
        }
    }
    /// 위험 구역 rises from the bottom as a card, the camera still showing above it (452:12705).
    @ViewBuilder private func dangerZoneCard(insets: EdgeInsets) -> some View {
        if model.editingDangerZones {
            Color.black.opacity(0.25).transition(.opacity)
                .onTapGesture {model.editingDangerZones=false}
            PreparationDangerZoneSheet(model:model,leading:insets.leading,trailing:insets.trailing) {model.editingDangerZones=false}
                .padding(.top,insets.top+30)
                .transition(.move(edge:.bottom))
                .zIndex(1)
        }
    }
    private func close() {
        guard !closing else {return}
        closing=true
        withAnimation(.easeIn(duration:ScanTransition.fade)) {veiled=true}
        Task { @MainActor in
            try? await Task.sleep(for:.seconds(ScanTransition.fade))
            ScreenOrientation.set(.portrait)
            try? await Task.sleep(for:.seconds(ScanTransition.rotation))
            var transaction=Transaction();transaction.disablesAnimations=true
            withTransaction(transaction) {dismiss()}
        }
    }
}

/// The design's confirmation (452:11160) in dark colours: a 300pt card with the title, the message and two
/// capsule buttons, the confirming one in the system blue.
struct ScanConfirmCard: View {
    let title: String
    let message: String
    let cancel: String
    let confirm: String
    let onCancel: () -> Void
    let onConfirm: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).onTapGesture(perform:onCancel)
            VStack(alignment:.leading,spacing:12) {
                Text(title).font(.system(size:17,weight:.semibold)).foregroundStyle(.white)
                Text(message).font(.system(size:15)).foregroundStyle(.white.opacity(0.8)).lineSpacing(3).fixedSize(horizontal:false,vertical:true)
                HStack(spacing:10) {
                    ScanCardButton(title:cancel,primary:false,action:onCancel)
                    ScanCardButton(title:confirm,action:onConfirm)
                }.padding(.top,8)
            }.padding(20).frame(width:316)
                .background(ScanChrome.alert.opacity(0.96),in:RoundedRectangle(cornerRadius:26,style:.continuous))
                .environment(\.colorScheme,.dark)
                .accessibilityAddTraits(.isModal)
        }
    }
}

/// Figma Ellipse 28: a #0088FF ellipse (134×60, blur 30, 86%) at the top edge over the Camera Control button,
/// breathing so the eye finds it.
struct CameraControlGlow: View {
    @State private var bright=false
    var body: some View {
        GeometryReader { geometry in
            Ellipse().fill(Color(red:0,green:136/255,blue:1).opacity(bright ? 0.86 : 0.35))
                .frame(width:134,height:60).blur(radius:22)
                .position(x:geometry.size.width*0.69,y:0)
        }.ignoresSafeArea().accessibilityHidden(true)
            .onAppear {withAnimation(.easeInOut(duration:1.1).repeatForever(autoreverses:true)) {bright=true}}
    }
}
