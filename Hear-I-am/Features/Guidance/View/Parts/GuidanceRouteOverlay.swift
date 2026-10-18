import SwiftUI

/// Legend over the live route camera, for checking saved points against the real floor.
struct GuidanceRouteOverlay: View {
    @ObservedObject var model: GuidanceViewModel
    var body: some View {
        VStack {
            HStack {
                Label(model.isPlanMode ? "실시간 AR · 무대 치수 스케일링" : "실시간 카메라 · 검증용",systemImage:"camera").font(.caption.weight(.semibold))
                Spacer()
                if model.isPlanMode {
                    Button {
                        _ = model.recalibratePlanOrigin(announce:true)
                    } label: {
                        Label("영점 재설정",systemImage:"scope")
                            .font(.caption.bold())
                            .padding(.horizontal,10).padding(.vertical,5)
                            .background(Color.hearGreen,in:Capsule())
                            .foregroundStyle(.black)
                    }.buttonStyle(.plain)
                }
            }.padding(10).background(.regularMaterial)
            Spacer()
            if !model.tracking.ready {
                Label("위치 확인 필요 · 지점 표시를 확인할 수 없어요",systemImage:"exclamationmark.triangle")
                    .font(.caption).padding(12).frame(maxWidth:.infinity).background(.regularMaterial)
            } else {
                VStack(alignment:.leading,spacing:6) {
                    if let cue=model.cue, model.phase == .guiding {
                        HStack {
                            Text(String(format:"목표까지 %.2f m",cue.distance)).font(.subheadline.bold().monospacedDigit())
                            Spacer()
                            if let pos=model.tracking.position, let first=model.activeRoute?.points.first {
                                Text(String(format:"출발 기준 (%+.2f, %+.2f)m",pos.x-first.x,pos.y-first.y))
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack(spacing:12) {
                        Label("저장 지점",systemImage:"circle.fill").foregroundStyle(Color.hearGreen)
                        if model.phase != .finishing && model.phase != .completed {
                            Label("현재 목표",systemImage:"scope").foregroundStyle(.orange)
                        }
                        Spacer(minLength:0)
                    }.font(.caption.bold())
                }.padding(12).background(.regularMaterial)
            }
        }
    }
}
