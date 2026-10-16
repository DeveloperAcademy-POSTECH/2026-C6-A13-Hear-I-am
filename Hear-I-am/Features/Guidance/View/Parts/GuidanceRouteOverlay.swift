import SwiftUI

/// Legend over the live route camera, for checking saved points against the real floor.
struct GuidanceRouteOverlay: View {
    @ObservedObject var model: GuidanceViewModel
    var body: some View {
        VStack {
            HStack {
                Label("실시간 카메라 · 검증용",systemImage:"camera").font(.caption.weight(.semibold))
                Spacer()
            }.padding(10).background(.regularMaterial)
            Spacer()
            if !model.tracking.ready {
                Label("위치 확인 필요 · 지점 표시를 확인할 수 없어요",systemImage:"exclamationmark.triangle")
                    .font(.caption).padding(12).frame(maxWidth:.infinity).background(.regularMaterial)
            } else {
                HStack(spacing:12) {
                    Label("저장 지점",systemImage:"circle.fill").foregroundStyle(Color.hearGreen)
                    if model.phase != .finishing && model.phase != .completed {
                        Label("현재 목표",systemImage:"scope").foregroundStyle(.orange)
                    }
                    Spacer(minLength:0)
                }.font(.caption.bold()).padding(12).background(.regularMaterial)
            }
        }.allowsHitTesting(false)
    }
}
