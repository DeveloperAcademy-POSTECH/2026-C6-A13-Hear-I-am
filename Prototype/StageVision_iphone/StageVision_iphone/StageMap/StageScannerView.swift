import SwiftUI
import ARKit

struct StageScannerView: View {
    var name: String
    var venue: String
    var pocMode = false
    var onFinish: (StageMap) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var controller = StageScanController()
    @State private var confirmReset = false

    var body: some View {
        GeometryReader { layout in
        ZStack {
            StageCamera(controller: controller, enablesGuidance: pocMode).ignoresSafeArea()
            // Same viewport center as ARSCNView.raycastQuery, including landscape safe areas.
            if controller.guidanceMap == nil {
            GeometryReader { geometry in
                Image(systemName: "plus.viewfinder")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(controller.hasAim ? .mint : .white)
                    .shadow(color: .black, radius: 3)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .ignoresSafeArea()
            .accessibilityLabel("경계 입력 조준점")
            .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 6) {
                HStack {
                    Button("취소") { controller.stop(); dismiss() }
                    Spacer()
                    Text("경계점 \(controller.pointCount)개").monospacedDigit()
                    Spacer()
                    Button("전체 초기화", role: .destructive) { confirmReset = true }
                }
                Text(controller.tracking).foregroundStyle(controller.normalTracking ? .mint : .orange)
                Text(controller.capabilities).font(.caption2)
            }
            .padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                if let map = controller.guidanceMap {
                    GuidancePanel(guide: $controller.guide, polygon: map.floorPolygon, liveAudio: true)
                        .frame(maxHeight: max(130, layout.size.height - 150))
                } else {
                Text(instruction).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                Text(controller.aimDescription).font(.caption).multilineTextAlignment(.center)
                controls
                }
            }
            .padding(14).frame(maxWidth: 660)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal).padding(.bottom, 8)
        }
        .confirmationDialog("입력한 점과 바닥 기준을 지우고 다시 스캔할까요?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("전체 초기화", role: .destructive) { controller.reset() }
        }
        .alert("스캔 안내", isPresented: Binding(get: { controller.error != nil }, set: { if !$0 { controller.error = nil } })) {
            Button("확인") { controller.error = nil }
        } message: { Text(controller.error ?? "") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { controller.invalidateSession("앱이 비활성화되었습니다. 전체 초기화 후 다시 스캔하세요.") }
        }
        .onDisappear { controller.stop() }
        }
    }
    private var instruction: String {
        if controller.needsRestart { return "세션이 중단되었습니다. 전체 초기화를 눌러주세요." }
        switch controller.phase {
        case .floor: return "1. 무대 위에서 바닥을 비추고 민트색 후보를 확인하세요.\n\(controller.candidateDescription)"
        case .origin: return "2. 무대 앞쪽 중앙 또는 기준점을 조준해 원점으로 지정하세요."
        case .front: return "3. 카메라를 객석 방향으로 향한 뒤 무대 앞쪽을 설정하세요."
        case .boundary: return "4. 경계를 한 방향으로 돌며 모서리를 추가하세요. 곡선은 여러 점으로 입력합니다."
        }
    }
    @ViewBuilder private var controls: some View {
        switch controller.phase {
        case .floor:
            HStack {
                Button("다른 바닥 후보") { controller.nextFloor() }.buttonStyle(.bordered)
                Button("이 바닥 확정") { controller.confirmFloor() }.buttonStyle(.borderedProminent)
            }.disabled(!controller.hasCandidate || !controller.normalTracking)
        case .origin:
            Button("조준 위치를 원점으로") { controller.confirmOrigin() }
                .buttonStyle(.borderedProminent).disabled(!controller.hasAim || !controller.normalTracking)
        case .front:
            Button("이 방향을 무대 앞쪽으로 설정") { controller.confirmFront() }
                .buttonStyle(.borderedProminent).disabled(!controller.normalTracking)
        case .boundary:
            HStack {
                Button("실행 취소") { controller.undo() }.disabled(controller.pointCount == 0)
                Button("경계점 추가") { controller.addPoint() }
                    .buttonStyle(.borderedProminent).disabled(!controller.hasAim || !controller.normalTracking)
                Button("경계 닫기") {
                    if let map = controller.finish(name: name, venue: venue) {
                        if pocMode { controller.beginGuidance(map: map) }
                        else { onFinish(map); controller.stop(); dismiss() }
                    }
                }.buttonStyle(.bordered).disabled(controller.pointCount < 3 || !controller.normalTracking)
            }
        }
    }
}

private struct StageCamera: UIViewRepresentable {
    let controller: StageScanController
    var enablesGuidance = false
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        controller.enablesGuidance = enablesGuidance
        controller.attach(view)
        return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
    static func dismantleUIView(_ uiView: ARSCNView, coordinator: ()) { uiView.session.pause() }
}
