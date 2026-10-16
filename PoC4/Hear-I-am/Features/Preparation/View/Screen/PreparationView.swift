import SwiftUI
import HearIAmCore

/// Landscape stage preparation over a full-screen camera.
struct PreparationView: View {
    @StateObject private var model=PreparationViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        GeometryReader { safe in
        VStack(spacing:0) {
            PreparationStepBar(model:model) {if model.exitNeedsConfirmation {model.confirmingExit=true} else {dismiss()}}
            GeometryReader { geometry in
            ZStack {
                CameraView(model:model.session).frame(maxWidth:.infinity,maxHeight:.infinity)
                if !model.supported {Color(.systemGray6)}
                if model.supported {
                Image(systemName:"plus").font(.system(size:30,weight:.light)).foregroundStyle(.white).shadow(color:.black,radius:2).accessibilityHidden(true)
                VStack {
                    HStack(alignment:.top) {
                        if model.step != .scan {PreparationMiniMap(model:model).frame(width:180,height:125).padding(10).background(.regularMaterial,in:RoundedRectangle(cornerRadius:18))}
                        Spacer(minLength:70)
                        PreparationGuideCard(model:model,maxHeight:max(76,geometry.size.height-152))
                            .frame(width:min(260,geometry.size.width*0.35)).background(.regularMaterial,in:RoundedRectangle(cornerRadius:20))
                    }
                    Spacer(minLength:8)
                    HStack {
                        Text(model.showsCrosshairHint)
                            .font(.caption).padding(8).background(.regularMaterial,in:Capsule())
                        Spacer()
                        PreparationControls(model:model)
                    }
                }.padding(.leading,safe.safeAreaInsets.leading+14)
                    .padding(.trailing,safe.safeAreaInsets.trailing+14)
                    .padding(.bottom,safe.safeAreaInsets.bottom+14)
                    .padding(.top,14)
                }
                if let intro=model.intro, model.supported {
                    Color.black.opacity(0.30)
                    PreparationIntro(step:model.step.rawValue,page:intro) {model.nextIntroPage()}.padding(16)
                }
                if !model.supported {
                    ContentUnavailableView("LiDAR 지원 iPhone이 필요해요",systemImage:"camera",description:Text("무대 준비는 실제 카메라와 LiDAR로 공간을 저장합니다. 시뮬레이터에서는 스캔할 수 없어요."))
                        .frame(maxWidth:500).background(.regularMaterial,in:RoundedRectangle(cornerRadius:20))
                }
                if model.interrupted {
                    VStack(spacing:14) {
                        Label("공간 추적이 잠시 멈췄어요",systemImage:"pause.circle").font(.headline)
                        Text("입력한 정보는 유지됩니다. 같은 공간을 비추고 다시 시작해주세요.").font(.subheadline)
                        ActionButton(title:"추적 다시 시작") {model.resumeTracking()}
                    }.padding(24).background(.regularMaterial,in:RoundedRectangle(cornerRadius:20))
                }
                if model.review {PreparationReviewCard(model:model)}
                if model.isSaving {
                    Color.black.opacity(0.35)
                    VStack(spacing:16) {ProgressView(); Text("무대 정보를 저장하는 중입니다…").font(.headline)}
                        .padding(32).background(.regularMaterial,in:RoundedRectangle(cornerRadius:22))
                }
            }.frame(width:geometry.size.width,height:geometry.size.height).clipped()
            }.ignoresSafeArea(.container,edges:[.horizontal,.bottom])
        }
        }.background(.white).preferredColorScheme(.light)
            .onAppear {ScreenOrientation.set(.landscape); model.appear()}
            .onDisappear {model.disappear(); ScreenOrientation.set(.portrait)}
            .onChange(of:scenePhase) {_,phase in model.scenePhaseChanged(phase)}
            .onChange(of:model.savedID) {_,id in if id != nil {dismiss()}}
            .alert("공간 스캔을 확정할까요?",isPresented:$model.confirmingScan) {
                Button("계속 스캔",role:.cancel) {}
                Button("공간 확정") {model.confirmScan()}
            } message:{Text("공연장과 백스테이지가 충분히 포함됐는지 확인해주세요. 확정 후에는 스캔 단계로 돌아갈 수 없습니다.")}
            .alert("확인해주세요",isPresented:Binding(get:{model.errorMessage != nil},set:{if !$0 {model.errorMessage=nil}})) {Button("확인",role:.cancel) {model.errorMessage=nil}} message:{Text(model.errorMessage ?? "")}
            .confirmationDialog("준비를 종료할까요? 저장하지 않은 내용은 사라집니다.",isPresented:$model.confirmingExit,titleVisibility:.visible) {
                Button("저장하지 않고 나가기",role:.destructive) {dismiss()}; Button("계속 준비",role:.cancel) {}
            }
    }
}
