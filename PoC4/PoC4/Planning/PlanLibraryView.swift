import SwiftUI
import PoC4Core

struct PlanLibraryView: View {
    @ObservedObject var library: StageLibrary
    @State private var editing: PerformancePlan?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    Text("공연 전에 동선을 그려보세요").font(.title3.bold())
                    Text("배치 연습용 도면입니다. 실제 스캔이나 안내와 연결되지 않아요.").font(.subheadline).foregroundStyle(.secondary)
                    if library.plans.isEmpty {
                        VStack(spacing:16) {
                            Image("StageEmpty").resizable().scaledToFit().frame(height:190)
                            Text("아직 저장한 공연이 없어요").font(.headline)
                            Button("첫 동선 그리기") {editing=PerformancePlan()}.buttonStyle(.borderedProminent)
                        }.frame(maxWidth:.infinity).padding(.vertical,35)
                    }
                    ForEach(library.plans) {plan in
                        Button {editing=plan} label: {
                            VStack(alignment:.leading,spacing:12) {
                                StageMap(points:plan.points,objects:plan.objects).frame(height:180)
                                HStack {Text(plan.name).font(.headline); Spacer(); Image(systemName:"chevron.right")}
                                Text("내부 지점 \(max(0,plan.points.count-2))개 · 기물 \(plan.objects.count)개").font(.subheadline).foregroundStyle(.secondary)
                                Text(plan.updatedAt,format:.dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                            }.padding(16).background(.white,in:RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(.gray.opacity(0.2)))
                        }.buttonStyle(.plain)
                    }
                }.padding(20)
            }.navigationTitle("공연 사전 저장")
                .toolbar {ToolbarItem(placement:.topBarTrailing) {Button {editing=PerformancePlan()} label:{Image(systemName:"plus")}.accessibilityLabel("공연 사전 저장 추가")}}
                .refreshable {await library.refresh()}
                .fullScreenCover(item:$editing) {plan in PlanEditorView(initial:plan,library:library)}
        }
    }
}
