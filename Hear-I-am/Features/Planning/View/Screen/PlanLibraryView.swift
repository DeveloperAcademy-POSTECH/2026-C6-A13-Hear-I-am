import SwiftUI
import HearIAmCore

/// Saved schematic plans. Independent from scanned stages and guidance.
struct PlanLibraryView: View {
    @ObservedObject var library: StageLibrary
    @StateObject private var model=PlanLibraryViewModel()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    Text("공연 전에 동선을 그려보세요").font(.title3.bold())
                    Text("실제 무대 치수(m)에 맞춰 동선을 설계하고 스캔 없이 바로 안내받을 수 있어요.").font(.subheadline).foregroundStyle(.secondary)
                    if library.plans.isEmpty {
                        VStack(spacing:16) {
                            Image("StageEmpty").resizable().scaledToFit().frame(height:190)
                            Text("아직 저장한 공연이 없어요").font(.headline)
                            Button("첫 동선 그리기") {model.create()}.buttonStyle(.borderedProminent)
                        }.frame(maxWidth:.infinity).padding(.vertical,35)
                    }
                    ForEach(library.plans) {plan in
                        Button {model.open(plan)} label: {PlanCard(plan:plan)}.buttonStyle(.plain)
                            .librarySelection(selecting:model.selection.selecting,selected:model.selection.contains(plan.id),onSelect:{
                                model.selection.begin(with:plan.id)
                            },onToggle:{model.selection.toggle(plan.id)})
                            .disabled(model.selection.deleting)
                    }
                }.padding(20)
            }.navigationTitle("공연 사전 저장")
                .toolbar {ToolbarItem(placement:.topBarTrailing) {Button {model.create()} label:{Image(systemName:"plus")}.accessibilityLabel("공연 사전 저장 추가").disabled(model.selection.selecting)}}
                .safeAreaInset(edge:.bottom) {
                    if model.selection.selecting {LibrarySelectionBar(count:model.selection.ids.count,busy:model.selection.deleting,cancel:{model.selection.cancel()},delete:{model.selection.confirmingDelete=true})}
                }
                .alert("선택한 공연 동선 \(model.selection.ids.count)개를 삭제할까요?",isPresented:$model.selection.confirmingDelete) {
                    Button("삭제",role:.destructive) {model.deleteSelected(in:library)}
                    Button("취소",role:.cancel) {}
                } message: {Text("저장한 사전 도면이 삭제되며 되돌릴 수 없어요. 실제 스캔 무대와 안내 기록은 유지돼요.")}
                .refreshable {await library.refresh()}
                .fullScreenCover(item:$model.editing) {plan in PlanEditorView(initial:plan,library:library)}
        }
    }
}
