import SwiftUI
import HearIAmCore

/// Overlay picker to apply a saved PerformancePlan onto the captured stage area.
struct PreparationPlanPicker: View {
    let plans: [PerformancePlan]
    let onSelect: (PerformancePlan) -> Void
    let onCancel: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(alignment:.leading,spacing:14) {
                HStack {
                    VStack(alignment:.leading,spacing:2) {
                        Text("사전 저장한 공연 동선 불러오기").font(.title3.bold())
                        Text("선택한 동선과 기물이 현재 무대 크기에 맞춰 AR 공간에 배치됩니다.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("닫기",action:onCancel).buttonStyle(.bordered)
                }
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:14) {
                        ForEach(plans) { plan in
                            Button { onSelect(plan) } label: {
                                VStack(alignment:.leading,spacing:8) {
                                    StageMap(showsLabels:false,points:plan.points,objects:plan.objects)
                                        .frame(width:200,height:130)
                                    Text(plan.name).font(.subheadline.bold()).foregroundStyle(Color.hearInk).lineLimit(1)
                                    Text("경로 \(plan.points.count)점 · 기물 \(plan.objects.count)개")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.padding(12).frame(width:224).background(.white,in:RoundedRectangle(cornerRadius:16))
                                    .overlay(RoundedRectangle(cornerRadius:16).stroke(Color.hearGreen.opacity(0.5),lineWidth:1.5))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical,4)
                }
            }.padding(22).frame(maxWidth:680).background(.regularMaterial,in:RoundedRectangle(cornerRadius:24)).padding(16)
        }
    }
}
