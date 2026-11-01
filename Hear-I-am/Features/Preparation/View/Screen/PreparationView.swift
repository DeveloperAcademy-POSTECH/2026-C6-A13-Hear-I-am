import SwiftUI
import HearIAmCore

/// Landscape stage preparation over a full-screen camera.
struct PreparationView: View {
    @ObservedObject var library: StageLibrary
    @StateObject private var model: PreparationViewModel
    private let onSaved: ((UUID) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
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
                Image(systemName:"plus").font(.system(size:34,weight:.light))
                    .foregroundStyle(!model.aimBlocked ? Color.black : .red).shadow(color:.white.opacity(0.8),radius:1.5)
                    .accessibilityHidden(true)
                // Figma 452:11120: everything floats on the camera; the plan sits on the right edge.
                VStack(spacing:0) {
                    PreparationStepBar(model:model) {if model.exitNeedsConfirmation {model.confirmingExit=true} else {dismiss()}}
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
                        PreparationGuideCard(model:model,maxHeight:max(160,safe.size.height-150))
                    }.padding(.trailing,insets.trailing+8).padding(.top,70).padding(.bottom,80)
                }
            }
            if let intro=model.intro, model.supported {
                Color.black.opacity(0.25)
                PreparationIntro(step:model.step.rawValue,page:intro) {model.intro=$0}.padding(16)
            }
            if !model.supported {
                VStack(spacing:16) {
                    ContentUnavailableView("LiDAR 지원 iPhone이 필요해요",systemImage:"camera",description:Text("무대 준비는 실제 카메라와 LiDAR로 공간을 저장합니다. 시뮬레이터에서는 스캔할 수 없어요."))
                    ScanCardButton(title:"나가기",primary:false) {dismiss()}.frame(width:160)
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
            .ignoresSafeArea()
        }.background(.black).preferredColorScheme(.light)
            .sheet(isPresented:$model.showingPhotos) {PreparationPhotosSheet(model:model)}
            .sheet(isPresented:$model.editingDangerZones) { PreparationDangerZoneSheet(model:model) }
            .onAppear {ScreenOrientation.set(.landscape); model.appear()}
            .onDisappear {model.disappear(); ScreenOrientation.set(.portrait)}
            .onChange(of:scenePhase) {_,phase in model.scenePhaseChanged(phase)}
            .onChange(of:model.savedID) {_,id in
                guard let id else {return}
                onSaved?(id)
                dismiss()
            }
            .alert("공간 스캔을 확정할까요?",isPresented:$model.confirmingScan) {
                Button("계속 스캔",role:.cancel) {}
                Button("공간 확정") {model.confirmScan()}
            } message:{Text("공연장과 백스테이지가 충분히 포함됐는지 확인해주세요. 확정 후에는 스캔 단계로 돌아갈 수 없습니다.")}
            .alert("이 위치를 경로점으로 추가할까요?",isPresented:$model.confirmingRouteHeight) {
                Button("다시 선택",role:.cancel) {model.cancelRouteHeight()}
                Button("이 위치로 추가") {model.confirmRouteHeight()}
            } message:{Text(model.routeHeightMessage)}
            .alert("확인해주세요",isPresented:Binding(get:{model.errorMessage != nil},set:{if !$0 {model.errorMessage=nil}})) {Button("확인",role:.cancel) {model.errorMessage=nil}} message:{Text(model.errorMessage ?? "")}
            .confirmationDialog("준비를 종료할까요? 저장하지 않은 내용은 사라집니다.",isPresented:$model.confirmingExit,titleVisibility:.visible) {
                Button("저장하지 않고 나가기",role:.destructive) {dismiss()}; Button("계속 준비",role:.cancel) {}
            }
    }
}
