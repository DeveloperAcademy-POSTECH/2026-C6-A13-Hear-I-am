import SwiftUI
import HearIAmCore

/// Select a saved plan as a display-only reference for manual stage preparation (Figma 971:29529).
struct PreparationPlanPicker: View {
    let plans: [PerformancePlan]
    @State private var selectedID: UUID?
    let onConfirm: (PerformancePlan) -> Void
    let onCancel: () -> Void
    init(plans: [PerformancePlan], initialID: UUID? = nil, onConfirm: @escaping (PerformancePlan) -> Void, onCancel: @escaping () -> Void,
         leading: CGFloat = 34, trailing: CGFloat = 34) {
        self.leading = leading
        self.trailing = trailing
        self.plans = plans
        _selectedID = State(initialValue: initialID)
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
    private var selectedPlan: PerformancePlan? {
        plans.first(where: { $0.id == selectedID })
    }
    /// Space kept clear of the Dynamic Island side and the other edge, as the screen's other controls.
    let leading: CGFloat
    let trailing: CGFloat
    var body: some View {
        // Figma 971:29529: a dark sheet across the whole width, 50pt below the top with 27pt top corners, holding
        // the title, the two buttons on the right and a row of saved routes.
        ZStack(alignment:.bottom) {
            Color.black.opacity(0.35).onTapGesture(perform:onCancel)
            VStack(alignment:.leading,spacing:18) {
                HStack(alignment:.top,spacing:10) {
                    VStack(alignment:.leading,spacing:6) {
                        Text(L("사전 저장한 공연 동선 불러오기")).font(HearFont.pretendard(.bold,size:24)).tracking(-0.72).foregroundStyle(.white)
                        Text(L("실제 무대의 가로·세로에 맞춰 옅은 잔상으로 보여줘요. 기물과 경로는 직접 찍어 등록하세요."))
                            .font(HearFont.pretendard(.medium,size:14)).foregroundStyle(.white.opacity(0.6))
                            // Two lines: the English is longer than one line beside the buttons and was cut off.
                            .lineLimit(2).fixedSize(horizontal:false,vertical:true)
                    }
                    Spacer(minLength:12)
                    Button(L("취소"),action:onCancel).font(HearFont.pretendard(.semibold,size:17)).foregroundStyle(.white)
                        .padding(.horizontal,22).frame(height:48).background(Color.white.opacity(0.1),in:Capsule())
                        .buttonStyle(.plain)
                    Button(L("참고 잔상 불러오기")) {if let plan=selectedPlan {onConfirm(plan)}}
                        .font(HearFont.pretendard(.semibold,size:17)).foregroundStyle(selectedPlan == nil ? .white.opacity(0.35) : ScanChrome.darkText)
                        .padding(.horizontal,22).frame(height:48)
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
                                            .padding(14).frame(width:256,height:156)
                                            .background(ScanChrome.illustration,in:RoundedRectangle(cornerRadius:20,style:.continuous))
                                        Image(systemName:isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size:24)).foregroundStyle(.white.opacity(isSelected ? 1 : 0.7)).padding(10)
                                    }
                                    Text(plan.name).font(HearFont.pretendard(.semibold,size:18)).foregroundStyle(.white).lineLimit(1).padding(.top,8)
                                    Text(L("경로 %@점 · 기물 %@개", plan.points.count, plan.objects.count))
                                        .font(HearFont.pretendard(.medium,size:14)).foregroundStyle(.white.opacity(0.6))
                                }
                                .padding(16)
                                .frame(width:288,alignment:.leading)
                                .background(Color.white.opacity(isSelected ? 0.18 : 0.08),in:RoundedRectangle(cornerRadius:24,style:.continuous))
                                .overlay(RoundedRectangle(cornerRadius:24,style:.continuous).stroke(.white.opacity(isSelected ? 0.8 : 0),lineWidth:2))
                                .contentShape(RoundedRectangle(cornerRadius:24,style:.continuous))
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }.padding(.vertical,4).padding(.horizontal,2)
                }
                Spacer(minLength:0)
            }
            .padding(.leading,leading-16).padding(.trailing,trailing-16).padding(.top,22)
            .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .padding(.horizontal,16)
            .background(Color(red:28/255,green:28/255,blue:30/255),in:UnevenRoundedRectangle(topLeadingRadius:27,topTrailingRadius:27,style:.continuous))
            .padding(.top,50)
            .environment(\.colorScheme,.dark)
            .accessibilityAddTraits(.isModal)
        }
    }
}
