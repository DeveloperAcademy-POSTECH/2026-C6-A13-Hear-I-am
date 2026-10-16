import SwiftUI
import SceneKit
import PoC4Core

struct SavedStagePreview: View {
    @StateObject private var model: SavedStagePreviewModel
    init(record: ScanManifest, store: ScanStore) { _model=StateObject(wrappedValue:SavedStagePreviewModel(record:record,store:store)) }
    var body: some View {
        VStack(spacing:16) {
            if let loaded=model.loaded {
                SavedMeshView(scan:loaded,wireframe:model.wireframe,fit:model.fit).clipShape(RoundedRectangle(cornerRadius:20))
                HStack {Toggle("표면 선 보기",isOn:$model.wireframe); Button("전체 보기") {model.fitAll()}.buttonStyle(.bordered)}
                Text("한 손가락 회전 · 두 손가락 이동 · 핀치 확대/축소").font(.caption)
                Text("스캔된 표면만 보여요. 실제 사용 전에는 현장에서 공간을 다시 확인해야 합니다.").font(.footnote).foregroundStyle(.secondary)
            } else if let error=model.error {
                ContentUnavailableView("3D 공간을 열 수 없어요",systemImage:"exclamationmark.triangle",description:Text(error))
                Button("다시 시도") {Task {await model.load()}}.buttonStyle(.borderedProminent)
            } else {ProgressView("스캔 공간을 불러오는 중입니다…").frame(maxWidth:.infinity,maxHeight:.infinity)}
        }.padding().navigationTitle(model.record.name).navigationBarTitleDisplayMode(.inline).task {await model.load()}
    }
}
