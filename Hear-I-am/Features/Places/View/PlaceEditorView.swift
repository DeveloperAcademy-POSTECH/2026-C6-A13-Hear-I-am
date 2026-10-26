import SwiftUI
import PhotosUI
import ImageIO
import HearIAmCore

struct PlaceEditorView: View {
    @ObservedObject var model: PlaceLibrary
    @ObservedObject var library: StageLibrary
    let original: PlaceEntry?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlaceEntry
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoLoading=false
    @State private var photoError: String?
    @State private var saving=false
    @State private var confirmingRemoval=false
    @State private var failure: String?
    init(model: PlaceLibrary, library: StageLibrary, place: PlaceEntry?) {
        self.model=model;self.library=library;original=place
        _draft=State(initialValue:place ?? PlaceEntry(name:"",address:"",kind:.rehearsal))
    }
    private var preview: UIImage? {photoData.flatMap {UIImage(data:$0)} ?? original.flatMap {model.photos[$0.photoID]}}
    private var valid: Bool {(try? draft.validate()) != nil && preview != nil && !photoLoading}
    private var validationMessage: String? {
        guard !draft.name.isEmpty, !draft.address.isEmpty else {return nil}
        do {try draft.validate();return nil} catch {return error.localizedDescription}
    }
    private var releasedCount: Int {
        guard let original else {return 0}
        let removed=Set(original.folders.map(\.id)).subtracting(draft.folders.map(\.id))
        return library.records.filter {scan in
            guard let d=model.index.destination(for:scan.id),d.placeID==original.id,let folder=d.folderID else {return false}
            return removed.contains(folder)
        }.count
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("필수 정보") {
                    PhotosPicker(selection:$photoItem,matching:.images,photoLibrary:.shared()) {
                        VStack(alignment:.leading,spacing:10) {
                            if let preview {
                                HStack {Text("장소 사진");Spacer();Label("사진 변경",systemImage:"photo")}.font(.subheadline)
                                PlacePhoto(image:preview).frame(height:150)
                            } else {
                                photoPlaceholder
                            }
                            if photoLoading {ProgressView("사진 준비 중")}
                        }.foregroundStyle(Color.hearInk)
                    }.disabled(saving)
                        .accessibilityLabel(preview == nil ? "장소 사진 추가, 필수" : "장소 사진 변경")
                        .accessibilityHint("사진 보관함을 엽니다")
                    if let photoError {Text(photoError).font(.caption).foregroundStyle(.red)}
                    LabeledContent("이름") {TextField("장소 이름",text:$draft.name).multilineTextAlignment(.trailing).accessibilityLabel("장소 이름, 필수")}
                    LabeledContent("위치") {TextField("주소 또는 위치",text:$draft.address,axis:.vertical).multilineTextAlignment(.trailing).accessibilityLabel("장소 위치, 필수")}
                    Picker("장소 유형",selection:$draft.kind) {ForEach(PlaceKind.allCases,id:\.self) {Text($0.title).tag($0)}}.pickerStyle(.segmented)
                }
                Section {
                    ForEach($draft.folders) {$folder in
                        HStack {
                            Image(systemName:"folder").accessibilityHidden(true)
                            TextField("폴더 이름",text:$folder.name).accessibilityLabel("하위 폴더 이름")
                            Button(role:.destructive) {let id=folder.id;draft.folders.removeAll {$0.id==id}} label:{Image(systemName:"minus.circle").font(.system(size:20)).frame(width:44,height:44)}
                                .buttonStyle(.borderless).accessibilityLabel("\(folder.name) 폴더 제거")
                        }
                    }
                    Button {draft.folders.append(.init(name:""))} label:{Label("폴더 추가",systemImage:"plus")}
                } header:{Text("하위 폴더 · 선택")} footer:{Text("대연습실·소연습실처럼 나눌 수 있어요. 폴더는 공연을 분류하는 용도로만 사용합니다.")}
                if let validationMessage {Section {Text(validationMessage).font(.subheadline).foregroundStyle(.red)}}
            }.disabled(saving).navigationTitle(original == nil ? "장소 등록" : "장소 수정").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) {Button("취소") {dismiss()}.disabled(saving)}
                    ToolbarItem(placement:.confirmationAction) {Button("저장") {if releasedCount>0 {confirmingRemoval=true} else {save()}}.fontWeight(.semibold).disabled(!valid || saving || model.busy)}
                }
                .interactiveDismissDisabled(saving)
                .task(id:photoItem) {await loadPhoto()}
                .alert("폴더에서 공연을 꺼낼까요?",isPresented:$confirmingRemoval) {
                    Button("취소",role:.cancel) {}
                    Button("저장") {save()}
                } message:{Text("삭제한 폴더의 공연 \(releasedCount)개는 장소 미지정으로 이동합니다. 스캔과 동선은 삭제되지 않습니다.")}
                .alert("저장하지 못했어요",isPresented:Binding(get:{failure != nil},set:{if !$0 {failure=nil}})) {Button("확인",role:.cancel) {failure=nil}} message:{Text(failure ?? "")}
        }.tint(.hearInk)
    }
    private var photoPlaceholder: some View {
        VStack(spacing:12) {
            Image(systemName:"plus").font(.system(size:30,weight:.light)).accessibilityHidden(true)
            Text("사진 추가 · 필수").font(.subheadline.weight(.semibold))
            Text("장소를 알아볼 수 있는 사진을 추가해주세요")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
        }
        .padding(.horizontal,16).padding(.vertical,24)
        .frame(maxWidth:.infinity,minHeight:170)
        .background(Color(.systemGray6).opacity(0.65),in:RoundedRectangle(cornerRadius:14))
        .overlay(RoundedRectangle(cornerRadius:14).stroke(Color.secondary.opacity(0.35),style:StrokeStyle(lineWidth:1,dash:[5,5])))
        .contentShape(RoundedRectangle(cornerRadius:14))
    }
    private func save() {
        saving=true
        Task {
            let success=await model.update {try await model.store.upsert(draft,photo:photoData)}
            saving=false
            if success {dismiss()}
            else {failure=model.error ?? "다시 시도해주세요.";model.error=nil}
        }
    }
    private func loadPhoto() async {
        guard let photoItem else {return}
        photoLoading=true;photoError=nil
        defer {if !Task.isCancelled {photoLoading=false}}
        do {
            guard let data=try await photoItem.loadTransferable(type:Data.self),data.count<=64*1_024*1_024 else {throw LabError.invalid("사진을 읽지 못했어요. 다른 사진을 선택해주세요.")}
            try Task.checkCancellation()
            guard let source=CGImageSourceCreateWithData(data as CFData,nil),
                  let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:1200] as CFDictionary),
                  let jpeg=UIImage(cgImage:cg).jpegData(compressionQuality:0.8),jpeg.count<=PlaceFolderStore.maximumPhotoBytes else {throw LabError.invalid("지원하지 않는 사진이에요. 다른 사진을 선택해주세요.")}
            photoData=jpeg
        } catch is CancellationError {} catch {photoError=error.localizedDescription}
    }
}
