import SwiftUI
import HearIAmCore

/// One saved plan in the list.
struct PlanCard: View {
    let plan: PerformancePlan
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            StageMap(points:plan.points,objects:plan.objects).frame(height:180)
            HStack {Text(plan.name).font(.headline); Spacer(); Image(systemName:"chevron.right")}
            Text(String(format:"무대 %.1f×%.1fm · 내부 지점 %d개 · 기물 %d개",plan.stageWidth,plan.stageDepth,max(0,plan.points.count-2),plan.objects.count))
                .font(.subheadline).foregroundStyle(.secondary)
            Text(plan.updatedAt,format:.dateTime.locale(Locale(identifier:"ko_KR")).month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
        }.padding(16).background(.white,in:RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(.gray.opacity(0.2)))
    }
}
