import SwiftUI
import SceneKit
import PoC4Core

struct SavedStagePreview: View {
    let record: ScanManifest
    let store: ScanStore
    @State private var loaded: LoadedScan?
    @State private var error: String?
    @State private var wireframe=false
    @State private var fit=0
    var body: some View {
        VStack(spacing:16) {
            if let loaded {
                SavedMeshView(scan:loaded,wireframe:wireframe,fit:fit).clipShape(RoundedRectangle(cornerRadius:20))
                HStack {Toggle("표면 선 보기",isOn:$wireframe); Button("전체 보기") {fit += 1}.buttonStyle(.bordered)}
                Text("한 손가락 회전 · 두 손가락 이동 · 핀치 확대/축소").font(.caption)
                Text("스캔된 표면만 보여요. 실제 사용 전에는 현장에서 공간을 다시 확인해야 합니다.").font(.footnote).foregroundStyle(.secondary)
            } else if let error {
                ContentUnavailableView("3D 공간을 열 수 없어요",systemImage:"exclamationmark.triangle",description:Text(error))
                Button("다시 시도") {Task {await load()}}.buttonStyle(.borderedProminent)
            } else {ProgressView("스캔 공간을 불러오는 중입니다…").frame(maxWidth:.infinity,maxHeight:.infinity)}
        }.padding().navigationTitle(record.name).navigationBarTitleDisplayMode(.inline).task {await load()}
    }
    private func load() async {
        error=nil
        do {loaded=try await store.load(record.id)} catch {self.error=error.localizedDescription}
    }
}
