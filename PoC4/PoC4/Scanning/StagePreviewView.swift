import SwiftUI
import SceneKit

/// Independent virtual camera; never changes the AR session or its coordinate frame.
struct StagePreviewView: View {
    @ObservedObject var model: ScanLabModel
    @Environment(\.dismiss) private var dismiss
    @State private var wireframe = false
    @State private var fitRequest = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                StagePreviewCanvas(model: model, wireframe: wireframe, fitRequest: fitRequest)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text("한 손가락 회전 · 두 손가락 이동 · 핀치 확대/축소")
                    .font(.footnote)
                HStack {
                    Toggle("와이어프레임", isOn: $wireframe)
                    Button("전체 보기") { fitRequest += 1 }.buttonStyle(.bordered)
                }
                Text("메시 \(model.meshCount)개 · 수집된 표면만 표시합니다. 빈 부분은 아직 관측되지 않았을 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("3D 형상 표시는 공간 복원이나 위치 검증 통과를 뜻하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("무대 3D 보기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
        }
        .onAppear { model.setPreviewVisible(true) }
        .onDisappear { model.setPreviewVisible(false) }
    }
}

private final class PreviewSCNView: SCNView {
    var fitWhenLaidOut: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        fitWhenLaidOut?()
    }
}

private struct StagePreviewCanvas: UIViewRepresentable {
    @ObservedObject var model: ScanLabModel
    let wireframe: Bool
    let fitRequest: Int

    final class Coordinator {
        let camera = SCNNode()
        var revision = -1
        var fitRequest = -1
        var wireframe: Bool?
        var fitted = false
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PreviewSCNView {
        let view = PreviewSCNView()
        view.scene = model.previewScene
        view.backgroundColor = UIColor(white: 0.08, alpha: 1)
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.worldUp = SCNVector3(0, 1, 0)
        view.preferredFramesPerSecond = 30
        view.antialiasingMode = .multisampling4X
        let camera = context.coordinator.camera
        camera.camera = SCNCamera()
        camera.camera?.zNear = 0.01
        camera.camera?.zFar = 2000
        view.pointOfView = camera
        return view
    }

    func updateUIView(_ view: PreviewSCNView, context: Context) {
        let state = context.coordinator
        let changed = state.revision != model.previewRevision
        if changed || state.wireframe != wireframe {
            for node in model.previewRoot.childNodes {
                node.geometry?.firstMaterial?.fillMode = wireframe ? .lines : .fill
            }
            state.revision = model.previewRevision
            state.wireframe = wireframe
        }
        view.fitWhenLaidOut = { [weak view] in
            guard let view, view.bounds.width > 0, view.bounds.height > 0 else { return }
            if !model.previewRoot.childNodes.isEmpty && (!state.fitted || state.fitRequest != fitRequest) {
            let bounds = model.previewRoot.boundingBox
            let low = SIMD3<Float>(bounds.min.x, bounds.min.y, bounds.min.z)
            let high = SIMD3<Float>(bounds.max.x, bounds.max.y, bounds.max.z)
            let center = (low + high) / 2
            let radius = max(simd_length(high - low) / 2, 0.5)
            // Fit a bounding sphere to the narrower screen dimension, with padding.
            let aspect = Float(max(view.bounds.width, 1) / max(view.bounds.height, 1))
            let halfFOV = Float.pi / 6
            let narrowFOV = atan(tan(halfFOV) * min(aspect, 1))
            let distance = radius / sin(narrowFOV) * 1.15
            let direction = simd_normalize(SIMD3<Float>(1, 0.8, 1))
            state.camera.camera?.fieldOfView = 60
            state.camera.simdPosition = center + direction * distance
            let target = SCNVector3(center.x, center.y, center.z)
            view.defaultCameraController.stopInertia()
            view.pointOfView = state.camera
            state.camera.look(at: target)
            view.defaultCameraController.target = target
            state.fitted = true
            state.fitRequest = fitRequest
            }
        }
        view.fitWhenLaidOut?()
    }
}
