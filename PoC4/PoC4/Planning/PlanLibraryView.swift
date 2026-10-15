import SwiftUI
import PoC4Core

struct PlanLibraryView: View {
    @ObservedObject var library: StageLibrary
    @State private var editing: PerformancePlan?
    @State private var selecting=false
    @State private var selectedIDs: Set<UUID> = []
    @State private var confirmingDelete=false
    @State private var deleting=false
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
                                Text(plan.updatedAt,format:.dateTime.locale(Locale(identifier:"ko_KR")).month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                            }.padding(16).background(.white,in:RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(.gray.opacity(0.2)))
                        }.buttonStyle(.plain)
                            .librarySelection(selecting:selecting,selected:selectedIDs.contains(plan.id),onSelect:{
                                selecting=true;selectedIDs.insert(plan.id)
                            },onToggle:{if !selectedIDs.insert(plan.id).inserted {selectedIDs.remove(plan.id)}})
                            .disabled(deleting)
                    }
                }.padding(20)
            }.navigationTitle("공연 사전 저장")
                .toolbar {ToolbarItem(placement:.topBarTrailing) {Button {editing=PerformancePlan()} label:{Image(systemName:"plus")}.accessibilityLabel("공연 사전 저장 추가").disabled(selecting)}}
                .safeAreaInset(edge:.bottom) {
                    if selecting {LibrarySelectionBar(count:selectedIDs.count,busy:deleting,cancel:{selecting=false;selectedIDs=[]},delete:{confirmingDelete=true})}
                }
                .confirmationDialog("선택한 공연 동선 \(selectedIDs.count)개를 삭제할까요?",isPresented:$confirmingDelete,titleVisibility:.visible) {
                    Button("공연 동선 삭제",role:.destructive) {deleteSelectedPlans()}
                    Button("취소",role:.cancel) {}
                } message: {Text("저장한 사전 도면이 삭제되며 되돌릴 수 없어요. 실제 스캔 무대와 안내 기록은 유지돼요.")}
                .refreshable {await library.refresh()}
                .fullScreenCover(item:$editing) {plan in PlanEditorView(initial:plan,library:library)}
        }
    }
    private func deleteSelectedPlans() {
        guard !deleting else {return}
        deleting=true
        let ids=selectedIDs
        Task {
            var failures:[String]=[]
            for id in ids {
                do {try await library.deletePlan(id)} catch {failures.append(error.localizedDescription)}
            }
            selectedIDs.formIntersection(Set(library.plans.map(\.id)))
            selecting = !selectedIDs.isEmpty;deleting=false
            if !failures.isEmpty {library.error="일부 공연 동선을 삭제하지 못했어요. 다시 시도해주세요. " + failures.joined(separator:"\n")}
        }
    }
}
