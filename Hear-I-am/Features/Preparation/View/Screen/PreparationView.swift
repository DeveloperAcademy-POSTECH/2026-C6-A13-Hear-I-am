import SwiftUI
import HearIAmCore

/// Landscape stage preparation over a full-screen camera.
struct PreparationView: View {
    @ObservedObject var library: StageLibrary
    @StateObject private var model: PreparationViewModel
    private let onSaved: ((UUID) -> Void)?
    private let performanceID: UUID?
    private var availablePlans: [PerformancePlan] {
        library.referencePlans(for: performanceID)
    }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    /// Black until the window has turned to landscape; black again while it turns back (see `ScanTransition`).
    @State private var veiled=true
    @State private var closing=false
    init(library: StageLibrary, initialPlan: PerformancePlan? = nil, performanceID: UUID? = nil, sceneName: String = "", onSaved: ((UUID) -> Void)? = nil) {
        self.library=library
        self.onSaved=onSaved
        self.performanceID=performanceID
        _model=StateObject(wrappedValue:PreparationViewModel(initialPlan:initialPlan, initialName:sceneName))
    }
    var body: some View {
        GeometryReader { safe in
        let insets=safe.safeAreaInsets
        ZStack {
            CameraView(model:model.session).frame(maxWidth:.infinity,maxHeight:.infinity)
            if !model.supported {Color(white:0.12)}
            #if DEBUG
            if PreparationViewModel.layoutPreview != nil {Color(red:0.62,green:0.55,blue:0.45)}
            #endif
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
                    HStack(alignment:.bottom) {
                        PreparationPhotoControls(model:model)
                        Spacer()
                        PreparationControls(model:model)
                    }
                }.padding(.leading,edge(insets).leading).padding(.trailing,edge(insets).trailing)
                    .padding(.top,26).padding(.bottom,27)
                // Undo and the step's tools sit in the middle of the whole screen, not of the space between the
                // side insets, which differ by orientation (Figma 971:15599; 11/07).
                PreparationToolGroup(model:model,hasPlans:!availablePlans.isEmpty)
                    .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.bottom)
                    .padding(.bottom,26)
                if model.step != .scan {
                    // Figma 971:29463: the panel's top is 80pt down and it runs past the screen's right edge.
                    PreparationGuideCard(model:model,maxHeight:max(160,safe.size.height+insets.top+insets.bottom-160))
                        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topTrailing)
                        .padding(.trailing,-PreparationGuideCard.bleed).padding(.top,80)
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
                PreparationPlanPicker(plans:availablePlans,initialID:model.selectedPlan?.id,onConfirm:{model.selectReferencePlan($0)},onCancel:{model.choosingPlan=false},
                                      leading:edge(insets).leading,trailing:edge(insets).trailing)
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
            PreparationMorePanel(model:model)
                .padding(.top,26+44+8).padding(.trailing,edge(insets).trailing)
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
    /// Figma 971:28541 measures the controls from the screen's edges, not the safe area: 56pt on the side of
    /// the Dynamic Island, 34pt on the other; 34pt each side where there is no island.
    private func edge(_ insets: EdgeInsets) -> (leading: CGFloat, trailing: CGFloat) {
        guard max(insets.leading,insets.trailing) > 30 else {return (34,34)}
        let orientation=(UIApplication.shared.connectedScenes.first as? UIWindowScene)?.effectiveGeometry.interfaceOrientation
        // Turned with its top to the left (landscapeRight), the island is on the left.
        return orientation == .landscapeLeft ? (34,56) : (56,34)
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

/// The scan confirmation in dark colours (452:11160; kept dark over 971:28264's light card, 11/07): a 316pt card
/// with the title, the message and two capsule buttons, the confirming one in the system blue.
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
