import SwiftUI
import HearIAmCore

/// Select a saved plan as a display-only reference for manual stage preparation (Figma 452:12642).
struct PreparationPlanPicker: View {
    let plans: [PerformancePlan]
    @State private var selectedID: UUID?
    let onConfirm: (PerformancePlan) -> Void
    let onCancel: () -> Void
    init(plans: [PerformancePlan], initialID: UUID? = nil, onConfirm: @escaping (PerformancePlan) -> Void, onCancel: @escaping () -> Void) {
        self.plans = plans
        _selectedID = State(initialValue: initialID)
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
    private var selectedPlan: PerformancePlan? {
        plans.first(where: { $0.id == selectedID })
    }
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(alignment:.leading,spacing:14) {
                HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:4) {
                        Text("사전 저장한 공연 동선 불러오기").font(.system(size:20,weight:.bold)).foregroundStyle(.white)
                        Text("실제 무대의 가로·세로에 맞춰 옅은 잔상으로 보여줘요. 기물과 경로는 직접 찍어 등록하세요.")
                            .font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                    }
                    Spacer(minLength:12)
                    Button("취소",action:onCancel).font(.system(size:17,weight:.semibold)).foregroundStyle(.white)
                        .padding(.horizontal,18).frame(height:44).background(Color.white.opacity(0.1),in:Capsule())
                        .buttonStyle(.plain)
                    Button("참고 잔상 불러오기") {if let plan=selectedPlan {onConfirm(plan)}}
                        .font(.system(size:17,weight:.semibold)).foregroundStyle(selectedPlan == nil ? .white.opacity(0.4) : ScanChrome.darkText)
                        .padding(.horizontal,18).frame(height:44)
                        .background(selectedPlan == nil ? Color.white.opacity(0.08) : .white,in:Capsule())
                        .buttonStyle(.plain).disabled(selectedPlan == nil)
                }
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:14) {
                        ForEach(plans) { plan in
                            let isSelected = selectedID == plan.id
                            Button {
                                selectedID = isSelected ? nil : plan.id
                            } label: {
                                VStack(alignment:.leading,spacing:6) {
                                    ZStack(alignment:.topTrailing) {
                                        StageMap(showsLabels:false,points:plan.points,objects:plan.objects,v3Style:true)
                                            .padding(8).frame(width:200,height:125)
                                            .background(ScanChrome.illustration,in:RoundedRectangle(cornerRadius:16,style:.continuous))
                                        Image(systemName:isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.title3).foregroundStyle(.white.opacity(isSelected ? 1 : 0.7)).padding(8)
                                    }
                                    Text(plan.name).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                                    Text("경로 \(plan.points.count)점 · 기물 \(plan.objects.count)개")
                                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                                }
                                .padding(12)
                                .frame(width:224)
                                .background(Color.white.opacity(isSelected ? 0.18 : 0.08),in:RoundedRectangle(cornerRadius:20))
                                .overlay(RoundedRectangle(cornerRadius:20).stroke(.white.opacity(isSelected ? 0.8 : 0),lineWidth:2))
                                .contentShape(RoundedRectangle(cornerRadius:20))
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }.padding(.vertical,4).padding(.horizontal,2)
                }
            }.padding(28).frame(maxWidth:760).scanCard().padding(16)
        }
    }
}
