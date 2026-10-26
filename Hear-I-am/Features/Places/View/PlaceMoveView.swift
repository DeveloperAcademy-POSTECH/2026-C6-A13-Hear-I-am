import SwiftUI
import HearIAmCore

struct PlaceMoveView: View {
    let scans: [ScanManifest]
    @ObservedObject var model: PlaceLibrary
    @ObservedObject var library: StageLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var selected: PlaceDestination?
    @State private var saving=false
    @State private var failure: String?
    init(scans: [ScanManifest], model: PlaceLibrary, library: StageLibrary) {
        self.scans=scans;self.model=model;self.library=library
        _selected=State(initialValue:scans.first.flatMap {model.index.destination(for:$0.id)})
    }
    var body: some View {
        NavigationStack {
            List {
                Section {row("장소 미지정",icon:"tray",destination:nil)} footer:{Text("공연의 스캔과 동선은 그대로 유지돼요.")}
                ForEach(PlaceSort.name.sorted(model.index.places)) {place in
                    Section {
                        row(place.name,icon:"mappin.and.ellipse",destination:.init(placeID:place.id))
                        ForEach(place.folders) {folder in
                            row(folder.name,icon:"folder",destination:.init(placeID:place.id,folderID:folder.id)).padding(.leading,18)
                        }
                    }
                }
            }.disabled(saving).navigationTitle("\(scans.count)개 공연 이동").navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.cancellationAction) {Button("취소") {dismiss()}.disabled(saving)}}
                .safeAreaInset(edge:.bottom) {
                    Button {save()} label:{Text(saving ? "이동 중" : "여기로 이동").font(.headline).frame(maxWidth:.infinity,minHeight:52).foregroundStyle(.white).background(Color.hearInk,in:RoundedRectangle(cornerRadius:16))}.disabled(saving || model.busy || model.loading).padding(20).background(.regularMaterial)
                }
                .alert("이동하지 못했어요",isPresented:Binding(get:{failure != nil},set:{if !$0 {failure=nil}})) {Button("확인",role:.cancel) {failure=nil}} message:{Text(failure ?? "")}
                .interactiveDismissDisabled(saving)
        }.tint(.hearInk)
    }
    private func row(_ name: String, icon: String, destination: PlaceDestination?) -> some View {
        Button {selected=destination} label:{HStack {Label(name,systemImage:icon);Spacer();Image(systemName:selected==destination ? "checkmark.circle.fill" : "circle").font(.title3)}.frame(minHeight:44)}
            .foregroundStyle(Color.hearInk).accessibilityAddTraits(selected==destination ? [.isSelected] : [])
    }
    private func save() {
        saving=true
        Task {
            let ids=Set(scans.map(\.id))
            let success=await model.update {
                let existing=Set(try await library.scans.list().map(\.id))
                guard ids.isSubset(of:existing) else {throw LabError.invalid("일부 공연이 삭제되었어요. 목록을 새로 확인해주세요.")}
                return try await model.store.assign(ids,to:selected)
            }
            saving=false
            if success {dismiss()}
            else {failure=model.error ?? "다시 시도해주세요.";model.error=nil}
        }
    }
}

struct PlaceRenameView: View {
    let scan: ScanManifest
    @ObservedObject var library: StageLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var saving=false
    @State private var failure: String?
    init(scan: ScanManifest, library: StageLibrary) {self.scan=scan;self.library=library;_name=State(initialValue:scan.name)}
    var body: some View {
        NavigationStack {
            Form {TextField("공연 이름",text:$name).accessibilityLabel("공연 이름")}
                .navigationTitle("공연 이름 변경").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) {Button("취소") {dismiss()}.disabled(saving)}
                    ToolbarItem(placement:.confirmationAction) {Button("저장") {
                        saving=true
                        Task {do {try await library.renameStage(scan.id,to:name.trimmingCharacters(in:.whitespacesAndNewlines));dismiss()} catch {failure=error.localizedDescription};saving=false}
                    }.disabled(saving || name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || name.count>80)}
                }.disabled(saving).interactiveDismissDisabled(saving)
                .alert("저장하지 못했어요",isPresented:Binding(get:{failure != nil},set:{if !$0 {failure=nil}})) {Button("확인",role:.cancel) {failure=nil}} message:{Text(failure ?? "")}
        }.tint(.hearInk)
    }
}
