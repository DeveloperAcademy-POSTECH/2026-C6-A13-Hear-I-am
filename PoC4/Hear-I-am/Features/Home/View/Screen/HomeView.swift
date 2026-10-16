import SwiftUI
import HearIAmCore

struct HomeView: View {
    @ObservedObject var library: StageLibrary
    @StateObject private var model=HomeViewModel()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:26) {
                    HStack {
                        BrandMark().frame(width:44,height:44)
                        Text("Hear I am").font(.largeTitle.bold())
                        Spacer()
                        Button {model.showSettingsNotice()} label: {Image(systemName:"gearshape").font(.title3).frame(width:44,height:44)}.accessibilityLabel("설정")
                    }
                    VStack(alignment:.leading,spacing:12) {
                        Text("무엇을 시작할까요?").font(.title3).foregroundStyle(.secondary)
                        HStack(spacing:12) {
                            HomeActionCard(title:"무대 준비하기",subtitle:"공간과 경로 저장",image:"ScanAction",dark:true) {model.preparing=true}.disabled(model.selection.selecting)
                            HomeActionCard(title:"안내 사용하기",subtitle:"저장한 무대 선택",image:"BeltAction",dark:false) {model.guiding=true}.disabled(model.selection.selecting)
                        }
                    }
                    if !library.groups.pinned.isEmpty {
                        VStack(alignment:.leading,spacing:14) {Text("고정한 무대").font(.title2.bold()); HomeStageList(library:library,model:model,records:library.groups.pinned)}
                    }
                    VStack(alignment:.leading,spacing:14) {
                        HStack {Text("최근 저장한 무대").font(.title2.bold()); Spacer(); Text("최근 저장순").font(.caption).foregroundStyle(.secondary)}
                        if library.loading && library.records.isEmpty {ProgressView().frame(maxWidth:.infinity)}
                        else if library.records.isEmpty {
                            VStack(spacing:12) {
                                Image("StageEmpty").resizable().scaledToFit().frame(height:155).accessibilityHidden(true)
                                Text("첫 무대를 준비해보세요").font(.headline)
                                Text("공간과 동선을 저장하면 여기에서 볼 수 있어요.").font(.subheadline).foregroundStyle(.secondary)
                            }.frame(maxWidth:.infinity).padding(20).background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:22))
                        } else if library.groups.recent.isEmpty {
                            Text("저장한 무대가 모두 위에 고정되어 있어요.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical)
                        } else {HomeStageList(library:library,model:model,records:library.groups.recent)}
                    }
                }.padding(20).padding(.bottom,16)
            }.background(Color(.systemBackground)).toolbar(.hidden,for:.navigationBar)
                .safeAreaInset(edge:.bottom) {
                    if model.selection.selecting {LibrarySelectionBar(count:model.selection.ids.count,busy:model.selection.deleting,cancel:{model.selection.cancel()},delete:{model.selection.confirmingDelete=true})}
                }
                .alert("선택한 무대 \(model.selection.ids.count)개를 삭제할까요?",isPresented:$model.selection.confirmingDelete) {
                    Button("삭제",role:.destructive) {model.deleteSelected(in:library)}
                    Button("취소",role:.cancel) {}
                } message: {Text("스캔 공간과 동선이 삭제되며 되돌릴 수 없어요. 고정도 해제됩니다. 완료한 안내 기록은 유지돼요.")}
                .alert("무대 이름 변경",isPresented:$model.showingRename) {
                    TextField("무대 이름",text:$model.editedName)
                    Button("취소",role:.cancel) {model.cancelRename()}
                    Button("저장") {model.rename(in:library)}.disabled(!model.canSaveName)
                } message: {Text("무대 이름을 80자 이내로 입력해주세요.")}
                .refreshable {await library.refresh()}
                .fullScreenCover(isPresented:$model.preparing,onDismiss:{Task {await library.refresh()}}) {PreparationView()}
                .fullScreenCover(isPresented:$model.guiding) {GuidanceView(library:library)}
                .alert("Hear I am",isPresented:Binding(get:{model.notice != nil},set:{if !$0 {model.notice=nil}})) {Button("확인",role:.cancel) {model.notice=nil}} message: {Text(model.notice ?? "")}
        }
    }
}
