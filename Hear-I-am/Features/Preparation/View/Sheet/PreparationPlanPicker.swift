import SwiftUI
import HearIAmCore

/// Overlay picker to select and apply a saved PerformancePlan onto the captured stage area.
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
                HStack {
                    VStack(alignment:.leading,spacing:2) {
                        Text("사전 저장한 공연 동선 불러오기").font(.title3.bold())
                        Text("적용할 동선을 선택한 뒤 ‘다음’을 눌러주세요.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ActionButton(title:"취소",primary:false,action:onCancel)
                    ActionButton(title:"다음",enabled:selectedPlan != nil) {
                        if let plan = selectedPlan { onConfirm(plan) }
                    }
                }
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:14) {
                        ForEach(plans) { plan in
                            let isSelected = selectedID == plan.id
                            Button {
                                selectedID = isSelected ? nil : plan.id
                            } label: {
                                VStack(alignment:.leading,spacing:8) {
                                    ZStack(alignment:.topTrailing) {
                                        StageMap(showsLabels:false,points:plan.points,objects:plan.objects)
                                            .frame(width:200,height:125)
                                        Image(systemName:isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundStyle(isSelected ? Color.hearGreen : .secondary)
                                            .padding(8)
                                    }
                                    Text(plan.name).font(.subheadline.bold()).foregroundStyle(Color.hearInk).lineLimit(1)
                                    Text("경로 \(plan.points.count)점 · 기물 \(plan.objects.count)개")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .frame(width:224)
                                .background(isSelected ? Color.hearGreen.opacity(0.12) : .white,in:RoundedRectangle(cornerRadius:16))
                                .overlay(RoundedRectangle(cornerRadius:16).stroke(isSelected ? Color.hearGreen : Color.gray.opacity(0.25),lineWidth:isSelected ? 2.5 : 1))
                                .contentShape(RoundedRectangle(cornerRadius:16))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.vertical,4).padding(.horizontal,2)
                }
            }.padding(22).frame(maxWidth:700).background(.regularMaterial,in:RoundedRectangle(cornerRadius:24)).padding(16)
        }
    }
}
