import SwiftUI
import HearIAmCore

/// One saved plan in the list.
struct PlanCard: View {
    let plan: PerformancePlan
    var onPrepare: (() -> Void)? = nil
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            StageMap(points:plan.points,objects:plan.objects).frame(height:180)
            HStack {Text(plan.name).font(.headline); Spacer(); Image(systemName:"chevron.right")}
            HStack {
                VStack(alignment:.leading,spacing:2) {
                    Text("내부 지점 \(max(0,plan.points.count-2))개 · 기물 \(plan.objects.count)개").font(.subheadline).foregroundStyle(.secondary)
                    Text(plan.updatedAt,format:.dateTime.locale(Locale(identifier:"ko_KR")).month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let onPrepare {
                    Button(action:onPrepare) {
                        Label("AR 무대 준비",systemImage:"viewfinder")
                            .font(.caption.bold())
                            .padding(.horizontal,12).padding(.vertical,8)
                            .background(Color.hearInk,in:Capsule())
                            .foregroundStyle(.white)
                    }.buttonStyle(.plain)
                }
            }
        }.padding(16).background(.white,in:RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(.gray.opacity(0.2)))
    }
}
