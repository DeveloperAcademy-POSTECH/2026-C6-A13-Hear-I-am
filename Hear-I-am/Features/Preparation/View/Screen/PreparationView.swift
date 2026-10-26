import SwiftUI
import HearIAmCore

/// Adaptive stage preparation; the crosshair always shares the AR view’s viewport.
struct PreparationView: View {
    @ObservedObject var library: StageLibrary
    @StateObject private var model: PreparationViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    init(library: StageLibrary, initialPlan: PerformancePlan? = nil) {
        self.library=library
        _model=StateObject(wrappedValue:PreparationViewModel(initialPlan:initialPlan))
    }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 650
            ZStack {
                VStack(spacing:12) {
                    PreparationStepBar(model:model) {if model.exitNeedsConfirmation {model.confirmingExit=true} else {dismiss()}}
                    // AnyLayout preserves the camera view and AR session when the available width changes.
                    let layout = wide ? AnyLayout(HStackLayout(alignment:.top,spacing:12)) : AnyLayout(VStackLayout(spacing:12))
                    layout {
                        camera
                            .frame(maxWidth:.infinity,maxHeight:.infinity)
                            .clipShape(RoundedRectangle(cornerRadius:20))
                        if model.supported {
                            PreparationGuideCard(model:model,maxHeight:wide ? max(80,geometry.size.height-200) : min(160,geometry.size.height*0.24))
                                .frame(width:wide ? 280 : nil)
                                .background(.regularMaterial,in:RoundedRectangle(cornerRadius:20))
                        }
                    }.frame(maxHeight:.infinity)
                    if model.supported {
                        ScrollView {
                            VStack(alignment:.leading,spacing:8) {
                                PreparationPhotoControls(model:model)
                                if model.step == .route, !model.draft.dangerZoneRoutePointLabels.isEmpty {
                                    Label("주의: \(model.draft.dangerZoneRoutePointLabels.joined(separator:" · ")) 위험 구역 포함",systemImage:"exclamationmark.triangle.fill")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                                if let hint=model.showsCrosshairHint {
                                    Text(hint).font(.caption).foregroundStyle(!model.aimBlocked ? .primary : Color.red)
                                }
                                WrappingControlsLayout {
                                    PreparationControls(model:model,hasPlans:!library.plans.isEmpty)
                                }
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }.scrollBounceBehavior(.basedOnSize)
                            .frame(maxHeight:geometry.size.height*(wide ? 0.36 : 0.28))
                            .fixedSize(horizontal:false,vertical:true)
                    }
                }.padding(.horizontal,16).padding(.bottom,8)
                    .accessibilityHidden(model.intro != nil || model.review || model.choosingPlan || model.interrupted || model.isSaving)
                if let intro=model.intro, model.supported {
                    Color.black.opacity(0.30)
                    PreparationIntro(step:model.step.rawValue,page:intro) {model.nextIntroPage()}.padding(16)
                }
                if model.interrupted {
                    ScrollView {
                        VStack(spacing:14) {
                            Label("공간 추적이 잠시 멈췄어요",systemImage:"pause.circle").font(.headline)
                            Text("입력한 정보는 유지됩니다. 같은 공간을 비추고 다시 시작해주세요.").font(.subheadline)
                            ActionButton(title:"추적 다시 시작") {model.resumeTracking()}
                        }.padding(24)
                    }.frame(maxWidth:480).fixedSize(horizontal:false,vertical:true)
                        .background(.regularMaterial,in:RoundedRectangle(cornerRadius:20)).padding(16)
                }
                if model.choosingPlan {
                    PreparationPlanPicker(plans:library.plans,initialID:model.selectedPlan?.id,onConfirm:{model.applyPlan($0)},onCancel:{model.choosingPlan=false})
                }
                if model.review {PreparationReviewCard(model:model)}
                if model.isSaving {
                    Color.black.opacity(0.35)
                    VStack(spacing:16) {ProgressView(); Text("무대 정보를 저장하는 중입니다…").font(.headline)}
                        .padding(32).background(.regularMaterial,in:RoundedRectangle(cornerRadius:22))
                }
            }
        }.background(.white).preferredColorScheme(.light)
            .sheet(isPresented:$model.showingPhotos) {PreparationPhotosSheet(model:model)}
            .sheet(isPresented:$model.editingDangerZones) { PreparationDangerZoneSheet(model:model) }
            .onAppear {ScreenOrientation.set(.allButUpsideDown); model.appear()}
            .onDisappear {model.disappear(); ScreenOrientation.set(.portrait)}
            .onChange(of:scenePhase) {_,phase in model.scenePhaseChanged(phase)}
            .onChange(of:model.savedID) {_,id in if id != nil {dismiss()}}
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
    private var camera: some View {
        GeometryReader { viewport in
            ZStack {
                CameraView(model:model.session)
                if !model.supported {
                    Color(.systemGray6)
                    ScrollView {
                        ContentUnavailableView("LiDAR 지원 iPhone이 필요해요",systemImage:"camera",description:Text("무대 준비는 실제 카메라와 LiDAR로 공간을 저장합니다. 시뮬레이터에서는 스캔할 수 없어요."))
                    }
                } else {
                    Image(systemName:"plus").font(.system(size:30,weight:.light))
                        .foregroundStyle(!model.aimBlocked ? .white : .red).shadow(color:.black,radius:2).accessibilityHidden(true)
                    if model.step != .scan {
                        VStack {
                            HStack {
                                PreparationMiniMap(model:model)
                                    .frame(width:viewport.size.height < 260 ? 112 : 160,height:viewport.size.height < 260 ? 76 : 108)
                                    .padding(8).background(.regularMaterial,in:RoundedRectangle(cornerRadius:14))
                                Spacer()
                            }
                            Spacer()
                        }.padding(8).allowsHitTesting(false)
                    }
                }
            }.frame(width:viewport.size.width,height:viewport.size.height)
        }
    }

}
