import SwiftUI
import PoC4Core

/// Portrait guidance. One AR view stays attached for the whole flow.
struct GuidanceView: View {
    @ObservedObject var library: StageLibrary
    @StateObject private var model=GuidanceViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(alignment:.leading,spacing:12) {
                Text(model.phase.stepLabel(targetName:model.targetName)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.hearGreen).padding(.horizontal,24)
                if model.phase.showsRouteCamera { GuidanceRouteHeader(model:model) }
                ZStack {
                    // Keep one AR view attached throughout the flow, including when the screen shows instructions.
                    CameraView(model:model.tracking).frame(maxWidth:.infinity,maxHeight:.infinity).accessibilityHidden(true)
                    if model.phase.showsRouteCamera { GuidanceRouteOverlay(model:model) }
                    else if model.phase.isCameraStep { GuidanceCameraPrompt(model:model) }
                    else if model.phase == .selection { Color(.systemBackground); GuidanceStageList(library:library,model:model) }
                    else { Color(.systemBackground); GuidanceInstruction(model:model) }
                }.clipShape(RoundedRectangle(cornerRadius:model.phase.showsRouteCamera ? 18 : 0))
                    .padding(.horizontal,model.phase.showsRouteCamera ? 20 : 0)
            }
            .navigationTitle("안내 사용하기").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    Button("나가기",systemImage:"xmark") { exit() }.labelStyle(.iconOnly)
                        .disabled(model.phase == .finishing || model.savingRecord || (model.phase == .completed && model.speaking))
                }
            }
            .safeAreaInset(edge:.bottom,spacing:0) { GuidanceControls(library:library,model:model,close:close,saveAndClose:saveAndClose) }
            .background(Color(.systemBackground))
            .alert("안내를 끝낼까요?",isPresented:$model.showExit) {
                Button("안내 끝내기",role:.destructive) { close() }
                Button("계속 사용하기",role:.cancel) { model.cancelExit() }
            } message: { Text("중간에 종료하면 도착 완료로 처리되지 않아요. 저장한 무대와 동선은 유지돼요.") }
        }
        .interactiveDismissDisabled()
        .onAppear {ScreenOrientation.set(.portrait)}
        .task {await library.refresh();model.selectionDescription(empty:library.records.isEmpty)}
        .onDisappear {model.finish();ScreenOrientation.set(.portrait)}
        .onChange(of:scenePhase) { _, value in
            // Camera permission sheets may make the scene inactive during restoration.
            if value == .active { model.setActive(true) }
            else if value == .background || (model.phase != .selection && model.phase != .restoring) { model.setActive(false) }
        }
    }
    private func close() { model.finish();dismiss() }
    private func saveAndClose() {
        Task { if await model.saveRecord(to:library) { close() } }
    }
    private func exit() {
        if model.phase == .completed {saveAndClose()}
        else if model.phase == .selection {close()}
        else {model.requestExit()}
    }
}
