import SwiftUI

struct BaseSpaceRestoreCard: View {
    @ObservedObject var model: PreparationViewModel
    var body: some View {
        VStack(spacing:10) {
            Text("기본 공간 위치 맞추기").font(.title3.bold())
            Text(model.spaceRequest?.base?.space?.checkpointNote ?? "등록할 때 지정한 확인점을 찾아주세요.").font(.headline)
            Text(model.session.status).font(.subheadline).multilineTextAlignment(.center)
            Text("같은 공간의 고정된 벽과 바닥을 비춘 뒤, 십자선을 실제 확인점에 맞춰주세요.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(spacing:8) {
                ActionButton(title:"다시 불러오기",primary:false,enabled:!model.busy) {model.resumeTracking()}
                ActionButton(title:"확인점 검증 후 계속",enabled:model.session.canVerify && !model.busy) {model.verifyBaseAndContinue()}
            }
            Text("위치가 맞지 않으면 나간 뒤 ‘공간 전체 새로 스캔’을 사용할 수 있어요.").font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(width:310).background(.regularMaterial,in:RoundedRectangle(cornerRadius:22))
    }
}
