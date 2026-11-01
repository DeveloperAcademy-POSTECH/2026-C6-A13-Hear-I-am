import SwiftUI
import HearIAmCore

/// Only the requested thumbnail/full image is read; errors stay local to this card.
struct SavedPhotoImage: View {
    let store: ScanStore
    let scanID: UUID
    let photo: ScanPhoto
    var thumbnail=true
    @State private var image: UIImage?
    @State private var failed=false
    var body: some View {
        Group {
            if let image {Image(uiImage:image).resizable().scaledToFit()}
            else if failed {Label("사진을 불러올 수 없어요",systemImage:"photo.badge.exclamationmark").font(.caption).padding()}
            else {ProgressView().padding()}
        }.task(id:"\(photo.id)-\(thumbnail)") {
            image=nil; failed=false
            do {
                let data=try await store.photoData(scanID:scanID,photoID:photo.id,thumbnail:thumbnail)
                guard !Task.isCancelled else {return}
                image=UIImage(data:data); failed=image==nil
            } catch {if !Task.isCancelled {failed=true}}
        }
    }
}

/// Compare the original JPEG and reconstructed scene at the same saved camera pose.
struct SavedPhotoViewpoint: View {
    let scan: LoadedScan
    let photo: ScanPhoto
    @StateObject private var model: SavedStagePreviewModel
    @Environment(\.dismiss) private var dismiss
    init(scan: LoadedScan,photo: ScanPhoto,store: ScanStore,cleanSurfaces: [ReplaySurfaceMesh],display: ReplayDisplay) {
        self.scan=scan;self.photo=photo
        _model=StateObject(wrappedValue:SavedStagePreviewModel(scan:scan,store:store,cleanSurfaces:cleanSurfaces,display:display))
    }
    private var aspect: CGFloat {CGFloat(photo.pixelWidth)/CGFloat(photo.pixelHeight)}
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment:.leading,spacing:12) {
                        Picker("공간 표시",selection:$model.display) {
                            ForEach(ReplayDisplay.allCases,id:\.self) {Text($0.rawValue).tag($0)}
                        }.pickerStyle(.segmented)
                        Text("촬영 위치에서 본 3D 공간").font(.subheadline.weight(.semibold))
                        SavedMeshView(scan:scan,model:model,photoViewpoint:photo)
                            .aspectRatio(aspect,contentMode:.fit)
                            .frame(maxWidth:.infinity,maxHeight:max(210,geometry.size.height*0.36))
                            .background(Color(.secondarySystemBackground),in:RoundedRectangle(cornerRadius:16))
                            .clipShape(RoundedRectangle(cornerRadius:16))
                            .accessibilityLabel("사진을 촬영한 위치와 방향에서 본 3D 공간")
                        Text("스캔 당시 사진").font(.subheadline.weight(.semibold))
                        SavedPhotoImage(store:model.store,scanID:scan.manifest.id,photo:photo,thumbnail:false)
                            .aspectRatio(aspect,contentMode:.fit)
                            .frame(maxWidth:.infinity,maxHeight:max(210,geometry.size.height*0.36))
                            .background(Color(.secondarySystemBackground),in:RoundedRectangle(cornerRadius:16))
                            .clipShape(RoundedRectangle(cornerRadius:16))
                        if photo.projection == nil {
                            Text("이전 사진은 화각·화면 회전 정보가 없어 가까운 구도로 표시해요.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("3D 화면에는 스캔된 표면만 나타나요.").font(.caption).foregroundStyle(.secondary)
                    }.padding(16)
                }
            }.navigationTitle("사진 시점 비교").navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.confirmationAction) {Button("닫기") {dismiss()}}}
        }
    }
}
