import SwiftUI

/// 2 / 4 · 현장 확인: crosshair and prompt while restoring the space and aiming at the checkpoint.
struct GuidanceCameraPrompt: View {
    @ObservedObject var model: GuidanceViewModel
    var body: some View {
        let restoring=model.phase == .restoring
        ZStack {
            Image(systemName:"plus").font(.system(size:30,weight:.medium)).foregroundStyle(.white)
                .shadow(color:.black,radius:2).accessibilityHidden(true)
            VStack {
                HStack {Label(restoring ? "공간 확인 중" : "확인점 검증",systemImage:"camera");Spacer()}
                    .font(.caption.weight(.semibold)).padding(12).background(.regularMaterial,in:Capsule())
                Spacer()
                VStack(alignment:.leading,spacing:10) {
                    if restoring {ProgressView()}
                    Text(restoring ? "공연장을 찾고 있어요" : "확인점 \(model.tracking.nextCheckpointNumber) / 2에\n조준점을 맞춰주세요").font(.title2.bold())
                    Text(restoring ? "휴대폰을 손에 들고 주변을 천천히 비춰주세요." : model.message).font(.subheadline)
                    if model.phase == .checkpoint && !model.tracking.canVerify { Text("위치 추적이 안정될 때까지 기다려주세요.").font(.caption) }
                }.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(.regularMaterial,in:RoundedRectangle(cornerRadius:22))
            }.padding(20)
        }
    }
}
