import SwiftUI
import ARKit
import RealityKit
import AVFoundation
import CoreMotion

/// **무대 위치 찾기 (R02 · R03 간이판)**
///
/// 세워 둔 iPhone 카메라로 사람의 바닥 위치를 미터 단위로 잡는다.
/// 계획서 R02의 첫 후보는 “수동 기준점 + 평면 좌표변환”이었지만, 이 화면은 LiDAR 가 있는 기종(iPhone 16 Pro Max)에서
/// ARKit 사람 추적(`ARBodyTrackingConfiguration`)이 주는 세계 좌표(미터)를 쓴다.
///
/// 사람 추적이 내부에서 LiDAR 를 쓰는지는 Apple 문서에 분명하지 않다. 그래서 **LiDAR 깊이(`sceneDepth`)를 직접 켜고**,
/// 사람의 골반 위치를 카메라 화면에 투영한 점의 LiDAR 깊이로 **따로 한 번 더** 위치를 잰다.
/// 두 값을 나란히 보여 주고 줄자와 비교해, 어느 쪽을 믿을지 실측으로 정한다.
///
/// 이 단계의 목적은 **위치가 믿을 만한가**를 먼저 보는 것이다. 소리는 위치가 확인된 뒤에 붙인다.
/// 좌표: 원점 = 세션을 시작할 때의 폰 위치. x = 폰에서 본 오른쪽, z = 폰 뒤쪽(앞은 −z).
/// 화면에는 알아보기 쉽게 “앞으로 몇 m · 옆으로 몇 m”로 바꿔 보여 준다.
///
/// 이 화면은 팀의 ①(제이스, 바닥 매핑)·②(톰, 위치 인식)와 겹친다. 소리 안내(③)를 시험하기 위한 간이판이다.
@MainActor
final class StageTracker: NSObject, ObservableObject, ARSessionDelegate {
    let arView = ARView(frame: .zero)

    /// 폰 기준 바닥 좌표(m): x 오른쪽 +, z 앞쪽 +(ARKit 의 −z 를 뒤집어 쓴다)
    @Published private(set) var person: SIMD2<Float>?
    @Published private(set) var target: SIMD2<Float>?
    @Published private(set) var lastSeen: Date?
    @Published private(set) var message = ""
    /// LiDAR 깊이로 잰 사람의 바닥 위치(같은 좌표계). 깊이를 못 읽으면 nil
    @Published private(set) var personLiDAR: SIMD2<Float>?
    /// LiDAR 깊이가 켜졌는지 한 줄
    @Published private(set) var lidarStatus = "확인 전"

    /// 화면 갱신을 1초에 5번 정도로 줄인다
    nonisolated(unsafe) private var lastDepthRead: TimeInterval = 0

    private var targetAnchor: AnchorEntity?
    /// 목표 정하기 단계에서만 화면을 눌러 목표를 찍을 수 있다(순서가 꼬이지 않게).
    var allowTargetTap = false
    /// 카메라를 켰는지
    @Published private(set) var started = false
    /// 지나온 길(폰 기준 바닥 좌표). 3cm 넘게 움직였을 때만 점을 더한다.
    @Published private(set) var trail: [SIMD2<Float>] = []
    @Published private(set) var trailLiDAR: [SIMD2<Float>] = []
    /// 카메라 화면 속 바닥에 띄우는 사람 표시
    private var personMarker: AnchorEntity?
    /// 바닥 높이. 목표를 찍으면 그 바닥 높이를 쓴다.
    private var floorY: Float?

    func clearTrail() {
        trail.removeAll()
        trailLiDAR.removeAll()
    }

    private static func append(_ p: SIMD2<Float>, to path: inout [SIMD2<Float>]) {
        if let last = path.last, simd_distance(last, p) < 0.03 { return }
        path.append(p)
        if path.count > 1500 { path.removeFirst(path.count - 1500) }
    }

    /// 화면 속 바닥에 파란 원을 사람 발밑에 띄운다.
    private func moveMarker(to world: SIMD3<Float>) {
        if personMarker == nil {
            let anchor = AnchorEntity(world: .zero)
            let disc = ModelEntity(mesh: .generateCylinder(height: 0.01, radius: 0.15),
                                   materials: [SimpleMaterial(color: .systemBlue.withAlphaComponent(0.7), isMetallic: false)])
            anchor.addChild(disc)
            arView.scene.addAnchor(anchor)
            personMarker = anchor
        }
        let y = floorY ?? (world.y - 0.95)
        personMarker?.position = SIMD3(world.x, y + 0.01, world.z)
    }

    var isSupported: Bool { ARBodyTrackingConfiguration.isSupported }

    /// 0.5초 넘게 사람을 못 보면 놓친 것으로 본다. 놓친 위치를 정상값처럼 쓰지 않기 위해서다(R03).
    func isTracking(at now: Date) -> Bool {
        guard let lastSeen else { return false }
        return now.timeIntervalSince(lastSeen) < 0.5
    }

    var distanceToTarget: Float? {
        guard let person, let target else { return nil }
        return simd_distance(person, target)
    }

    func start() {
        guard isSupported else {
            message = "이 기기는 사람 추적을 지원하지 않아요"
            return
        }
        let config = ARBodyTrackingConfiguration()
        config.planeDetection = [.horizontal]
        if ARBodyTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
            lidarStatus = "켜짐"
        } else {
            let hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
            lidarStatus = hasLiDAR ? "이 폰엔 있지만 사람 추적과 같이 못 켜요" : "이 폰엔 LiDAR가 없어요"
        }
        arView.session.delegate = self
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        started = true
        message = "폰을 세워 두고 움직이지 마세요"
    }

    func stop() {
        arView.session.pause()
    }

    /// 화면을 누른 곳의 바닥을 목표로 삼는다.
    func setTarget(at point: CGPoint) {
        guard let hit = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal).first else {
            message = "바닥을 못 찾았어요. 바닥이 보이는 곳을 눌러 주세요"
            return
        }
        let p = hit.worldTransform.columns.3
        target = SIMD2(p.x, -p.z)
        floorY = p.y
        targetAnchor.map { arView.scene.removeAnchor($0) }
        let anchor = AnchorEntity(world: hit.worldTransform)
        let marker = ModelEntity(mesh: .generateCylinder(height: 0.02, radius: 0.25),
                                 materials: [SimpleMaterial(color: .green.withAlphaComponent(0.6), isMetallic: false)])
        anchor.addChild(marker)
        arView.scene.addAnchor(anchor)
        targetAnchor = anchor
        message = "목표를 정했어요"
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let body = anchors.compactMap({ $0 as? ARBodyAnchor }).first else { return }
        let tracked = body.isTracked
        let p = body.transform.columns.3
        Task { @MainActor in
            guard tracked else { return }
            let floor = SIMD2(p.x, -p.z)
            self.person = floor
            self.lastSeen = Date()
            Self.append(floor, to: &self.trail)
            self.moveMarker(to: SIMD3(p.x, p.y, p.z))
        }
    }

    /// LiDAR 깊이로 사람 위치를 한 번 더 잰다.
    /// 골반(몸 기준점)을 카메라 영상에 투영 → 그 자리 주변 5×5 깊이의 중앙값 → 3D 점으로 되돌림 → 바닥 좌표.
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard frame.timestamp - lastDepthRead > 0.2 else { return }
        lastDepthRead = frame.timestamp
        guard let depthData = frame.sceneDepth,
              let body = frame.anchors.compactMap({ $0 as? ARBodyAnchor }).first, body.isTracked
        else {
            if frame.sceneDepth == nil { return }
            Task { @MainActor in self.personLiDAR = nil }
            return
        }
        let camera = frame.camera
        let image = camera.imageResolution
        let hip = body.transform.columns.3
        let pt = camera.projectPoint(SIMD3(hip.x, hip.y, hip.z), orientation: .landscapeRight, viewportSize: image)
        let map = depthData.depthMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        let dw = CVPixelBufferGetWidth(map), dh = CVPixelBufferGetHeight(map)
        let row = CVPixelBufferGetBytesPerRow(map)
        guard let base = CVPixelBufferGetBaseAddress(map) else { return }
        let cu = Int(pt.x / image.width * CGFloat(dw)), cv = Int(pt.y / image.height * CGFloat(dh))
        var samples: [Float] = []
        for dy in -2...2 {
            for dx in -2...2 {
                let u = cu + dx, v = cv + dy
                guard u >= 0, v >= 0, u < dw, v < dh else { continue }
                let d = base.advanced(by: v * row).assumingMemoryBound(to: Float32.self)[u]
                if d.isFinite, d > 0.1 { samples.append(d) }
            }
        }
        guard !samples.isEmpty else {
            Task { @MainActor in self.personLiDAR = nil }
            return
        }
        let depth = samples.sorted()[samples.count / 2]
        // 영상 좌표 → 카메라 좌표(x 오른쪽, y 위, −z 앞) → 세계 좌표
        let k = camera.intrinsics
        let fx = k[0][0], fy = k[1][1], cx = k[2][0], cy = k[2][1]
        let camPoint = SIMD4<Float>((Float(pt.x) - cx) * depth / fx,
                                    -(Float(pt.y) - cy) * depth / fy,
                                    -depth, 1)
        let world = camera.transform * camPoint
        let floor = SIMD2(world.x, -world.z)
        Task { @MainActor in
            self.personLiDAR = floor
            Self.append(floor, to: &self.trailLiDAR)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let text = error.localizedDescription
        Task { @MainActor in self.message = "카메라 오류: \(text)" }
    }
}

/// ARView 를 SwiftUI 에 붙이고, 누른 곳을 목표로 넘긴다.
private struct ARViewContainer: UIViewRepresentable {
    let tracker: StageTracker

    func makeUIView(context: Context) -> ARView {
        let view = tracker.arView
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(tracker: tracker) }

    final class Coordinator: NSObject {
        let tracker: StageTracker
        init(tracker: StageTracker) { self.tracker = tracker }
        @MainActor @objc func tapped(_ g: UITapGestureRecognizer) {
            guard tracker.allowTargetTap else { return }
            tracker.setTarget(at: g.location(in: g.view))
        }
    }
}

/// 위에서 내려다본 동선 지도. 폰은 아래 가운데, 카메라가 보는 쪽이 위.
/// 보이는 범위는 사람·목표·지나온 길이 다 들어오게 저절로 넓어진다(가로세로 같은 비율).
private struct StageMap: View {
    let person: SIMD2<Float>?
    let personLiDAR: SIMD2<Float>?
    let target: SIMD2<Float>?
    let trail: [SIMD2<Float>]
    let trailLiDAR: [SIMD2<Float>]
    let tracking: Bool
    let arriveRadius: Float

    var body: some View {
        Canvas { ctx, size in
            let pts = trail + trailLiDAR + [person, personLiDAR, target].compactMap { $0 }
            var forward: Float = 4, side: Float = 2
            for p in pts {
                forward = max(forward, p.y * 1.15 + 0.5)
                side = max(side, abs(p.x) * 1.15 + 0.5)
            }
            let scale = min(size.width / CGFloat(side * 2), (size.height - 28) / CGFloat(forward))
            let origin = CGPoint(x: size.width / 2, y: size.height - 18)
            func pt(_ p: SIMD2<Float>) -> CGPoint {
                CGPoint(x: origin.x + CGFloat(p.x) * scale, y: origin.y - CGFloat(p.y) * scale)
            }

            // 1m 격자와 거리 글자
            var m = 1
            while CGFloat(m) * scale < origin.y {
                let y = origin.y - CGFloat(m) * scale
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                           with: .color(.secondary.opacity(0.18)), lineWidth: 1)
                ctx.draw(Text("\(m)m").font(.caption2).foregroundStyle(.secondary),
                         at: CGPoint(x: 16, y: y - 8))
                m += 1
            }
            ctx.stroke(Path { $0.move(to: origin); $0.addLine(to: CGPoint(x: origin.x, y: 0)) },
                       with: .color(.secondary.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            // 목표: 점 + 도착 범위
            if let target {
                let c = pt(target)
                let r = CGFloat(arriveRadius) * scale
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(.green.opacity(0.15)))
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                           with: .color(.green.opacity(0.6)), lineWidth: 1.5)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)), with: .color(.green))
            }

            // 지나온 길: 오래된 쪽일수록 흐리게
            func drawTrail(_ path: [SIMD2<Float>], _ color: Color, _ width: CGFloat) {
                guard path.count > 1 else { return }
                for i in 1..<path.count {
                    let alpha = 0.12 + 0.88 * Double(i) / Double(path.count)
                    ctx.stroke(Path { $0.move(to: pt(path[i - 1])); $0.addLine(to: pt(path[i])) },
                               with: .color(color.opacity(alpha)),
                               style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
            }
            drawTrail(trailLiDAR, .purple, 2)
            drawTrail(trail, .blue, 3.5)

            // 지금 위치
            if let personLiDAR {
                let c = pt(personLiDAR)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(.purple))
            }
            if let person {
                let c = pt(person)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20)),
                         with: .color(tracking ? .blue : .gray))
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20)),
                           with: .color(.white), lineWidth: 2.5)
            }

            // 폰
            let phone = CGRect(x: origin.x - 9, y: origin.y - 4, width: 18, height: 12)
            ctx.fill(Path(roundedRect: phone, cornerRadius: 3), with: .color(.primary))
            ctx.fill(Path { p in
                p.move(to: CGPoint(x: origin.x, y: origin.y - 14))
                p.addLine(to: CGPoint(x: origin.x - 6, y: origin.y - 6))
                p.addLine(to: CGPoint(x: origin.x + 6, y: origin.y - 6))
            }, with: .color(.primary.opacity(0.6)))
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemBackground)))
        .accessibilityLabel("위에서 본 동선 지도. 파란 점과 선이 사람과 지나온 길, 보라는 LiDAR로 잰 위치, 초록이 목표, 아래가 폰")
    }
}

/// 숫자 하나를 크게 보여 주는 칸
private struct StatTile: View {
    let title: String
    let value: String
    var tint: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemBackground)))
    }
}

/// 둥근 카드
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }
}

private struct Pill: View {
    let text: String
    let symbol: String
    let color: Color
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color, in: Capsule())
            .foregroundStyle(.white)
    }
}

struct StageView: View {
    /// true 면 S2: 목표 자리에서 소리를 내고 그쪽으로 걸어간다
    var withSound = false
    @StateObject private var tracker = StageTracker()
    @StateObject private var beacon = StageBeaconAudio()
    @EnvironmentObject private var store: TrialStore
    @State private var useLiDAR = false
    @State private var walking = false
    @State private var walkStart = Date()
    @State private var startDistance: Float?
    @State private var nearSince: Date?
    @State private var lostNow = false
    @State private var loop: Task<Void, Never>?
    /// 차근차근 단계. 앞 단계를 끝내야 다음 버튼이 켜진다.
    private enum Step: Int { case camera, person, target, front, walk }
    @State private var step: Step = .camera
    @State private var recognizing = false
    @State private var seenSince: Date?

    var body: some View {
        VStack(spacing: 0) {
            ARViewContainer(tracker: tracker)
                .frame(maxWidth: .infinity)
                .frame(height: 250)
                .overlay(alignment: .topLeading) {
                    TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
                        let on = tracker.isTracking(at: ctx.date)
                        HStack(spacing: 6) {
                            Pill(text: on ? "사람 찾음" : "사람 못 찾음",
                                 symbol: on ? "figure.walk" : "questionmark", color: on ? .green : .red)
                            Pill(text: "LiDAR \(tracker.lidarStatus == "켜짐" ? "켜짐" : "꺼짐")",
                                 symbol: "dot.radiowaves.forward",
                                 color: tracker.lidarStatus == "켜짐" ? .purple : .gray)
                        }
                        .padding(10)
                    }
                }
            ScrollView {
                VStack(spacing: 12) {
                    stepsCard
                    mapCard
                    if tracker.lidarStatus != "켜짐" && tracker.started {
                        Text("LiDAR: \(tracker.lidarStatus)").font(.footnote).foregroundStyle(.orange)
                    }
                    if !tracker.message.isEmpty {
                        Text(tracker.message).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle(withSound ? "카메라 + 소리 따라 걷기" : "무대 위치 찾기")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if withSound { beacon.prepare() }
        }
        .onDisappear {
            stopWalk(result: nil)
            beacon.shutdown()
            tracker.stop()
        }
    }

    // MARK: 동선 지도

    private var mapCard: some View {
        Card {
            HStack {
                Text("위에서 본 동선").font(.headline)
                Spacer()
                Button {
                    tracker.clearTrail()
                } label: {
                    Label("동선 지우기", systemImage: "eraser")
                }
                .font(.subheadline)
            }
            TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                let on = tracker.isTracking(at: ctx.date)
                VStack(spacing: 10) {
                    StageMap(person: tracker.person, personLiDAR: tracker.personLiDAR, target: tracker.target,
                             trail: tracker.trail, trailLiDAR: tracker.trailLiDAR, tracking: on, arriveRadius: 0.4)
                        .frame(height: 340)
                    HStack(spacing: 14) {
                        legend(.blue, "사람 추적")
                        legend(.purple, "LiDAR")
                        legend(.green, "목표 · 도착 범위")
                    }
                    .font(.caption)
                    HStack(spacing: 8) {
                        StatTile(title: "폰에서", value: currentPerson.map { String(format: "%.2fm", simd_length($0)) } ?? "—")
                        StatTile(title: "목표까지",
                                 value: zip(currentPerson, tracker.target).map { String(format: "%.2fm", simd_distance($0, $1)) } ?? "—",
                                 tint: zip(currentPerson, tracker.target).map { simd_distance($0, $1) <= 0.4 ? .green : .primary } ?? .primary)
                        StatTile(title: "두 방식 차이",
                                 value: zip(tracker.person, tracker.personLiDAR).map { String(format: "%.2fm", simd_distance($0, $1)) } ?? "—",
                                 tint: zip(tracker.person, tracker.personLiDAR).map { simd_distance($0, $1) <= 0.2 ? .green : .orange } ?? .primary)
                    }
                    if let p = currentPerson {
                        Text(String(format: "%@ 위치 · 앞 %.2fm · %@ %.2fm",
                                    useLiDAR ? "LiDAR" : "사람 추적", p.y, p.x >= 0 ? "오른쪽" : "왼쪽", abs(p.x)))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).foregroundStyle(.secondary)
        }
    }

    // MARK: S2 · 소리

    // MARK: 단계

    private var stepsCard: some View {
        Card {
            HStack {
                Text(withSound ? "차근차근 (S2)" : "차근차근 (S1)").font(.headline)
                Spacer()
                if step != .camera {
                    Button("처음부터") { resetAll() }.font(.subheadline)
                }
            }
            stepRow(.camera, "카메라 켜기",
                    "폰을 삼각대나 선반에 세워 걷는 곳이 다 보이게 하고, 켠 뒤엔 움직이지 마세요") {
                Button("카메라 켜기") {
                    tracker.start()
                    step = .person
                }
            }
            stepRow(.person, "사람 인식",
                    "걷는 사람이 화면 안에 몸 전체가 나오게 서요. 1.5초 동안 계속 보이면 다음으로 넘어가요") {
                TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
                    if recognizing {
                        let on = tracker.isTracking(at: ctx.date)
                        Label(on ? "보고 있어요… 그대로 계세요" : "아직 못 찾았어요 — 몸 전체가 나오게 서 주세요",
                              systemImage: on ? "figure.stand" : "questionmark")
                            .font(.subheadline).foregroundStyle(on ? .green : .orange)
                            .onChange(of: ctx.date) { _, now in checkRecognized(at: now) }
                    } else {
                        Button("사람 인식 시작") { recognizing = true; seenSince = nil }
                    }
                }
            }
            stepRow(.target, "목표 정하기",
                    "위 카메라 화면 속 바닥을 눌러 목표(초록)를 찍어요. 다시 누르면 바뀌어요") {
                if let t = tracker.target {
                    Text(String(format: "목표: 앞 %.2fm · %@ %.2fm", t.y, t.x >= 0 ? "오른쪽" : "왼쪽", abs(t.x)))
                        .font(.caption.monospacedDigit())
                    Button(withSound ? "이 목표로 정하기" : "이 목표로 정하고 재기") {
                        tracker.allowTargetTap = false
                        step = withSound ? .front : .walk
                    }
                } else {
                    Text("카메라 화면 속 바닥을 눌러 주세요").font(.subheadline).foregroundStyle(.orange)
                }
            }
            if withSound {
                stepRow(.front, "정면 맞추기",
                        "걷는 사람은 이 폰에 연결된 AirPods를 끼고, 폰(카메라)을 바라보고 서요") {
                    if beacon.headReady {
                        Button("지금 폰을 보고 있어요 — 정면 맞추기") {
                            beacon.calibrate()
                            step = .walk
                        }
                    } else {
                        Text("AirPods 고개 방향을 기다리는 중… AirPods를 끼고 이 폰에 연결해 주세요")
                            .font(.subheadline).foregroundStyle(.orange)
                    }
                }
                stepRow(.walk, "걷기",
                        "눈 감고 ‘쏴’ 소리 나는 쪽으로 걸어가요. 가까울수록 커지고, 40cm 안에 1초 있으면 “도착”") {
                    Picker("위치는 무엇으로", selection: $useLiDAR) {
                        Text("위치: 사람 추적").tag(false)
                        Text("위치: LiDAR").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .disabled(walking)
                    if walking {
                        if lostNow {
                            Label("사람을 놓쳐서 소리를 멈췄어요", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        Button("멈추기", role: .destructive) { stopWalk(result: "중단") }
                    } else {
                        HStack {
                            Button("걷기 시작") {
                                tracker.clearTrail()
                                startWalk()
                            }
                            Button("목표 다시 정하기") { goToTarget() }.buttonStyle(.bordered)
                        }
                    }
                    if let last = beacon.lastResult {
                        Text(last).font(.footnote)
                    }
                }
            } else {
                stepRow(.walk, "재기",
                        "줄자로 폰 바로 아래 바닥에서 사람 발까지 재서, 아래 ‘폰에서’ 숫자와 비교해요") {
                    Button("목표 다시 정하기") { goToTarget() }.buttonStyle(.bordered)
                }
            }
        }
    }

    /// 단계 한 줄. 지난 단계는 체크, 지금 단계만 버튼이 보이고, 뒤 단계는 잠겨 있다.
    @ViewBuilder
    private func stepRow<Action: View>(_ s: Step, _ title: String, _ detail: String,
                                       @ViewBuilder action: () -> Action) -> some View {
        let done = s.rawValue < step.rawValue
        let current = s == step
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : (current ? Color.yellow : Color.secondary.opacity(0.25)))
                    .frame(width: 28, height: 28)
                if done {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                } else {
                    Text("\(s.rawValue + 1)").font(.subheadline.weight(.bold))
                        .foregroundStyle(current ? .black : .secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(current || done ? .primary : .secondary)
                if current {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                    action()
                        .buttonStyle(.borderedProminent)
                        .tint(.yellow)
                        .foregroundStyle(.black)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func checkRecognized(at now: Date) {
        guard recognizing, step == .person else { return }
        if tracker.isTracking(at: now) {
            if seenSince == nil { seenSince = now }
            if let since = seenSince, now.timeIntervalSince(since) >= 1.5 {
                recognizing = false
                goToTarget()
            }
        } else {
            seenSince = nil
        }
    }

    private func goToTarget() {
        stopWalk(result: nil)
        tracker.allowTargetTap = true
        step = .target
    }

    private func resetAll() {
        stopWalk(result: nil)
        tracker.allowTargetTap = false
        tracker.clearTrail()
        recognizing = false
        step = .person
    }

    /// 지금 쓸 사람 위치(폰 기준 바닥 좌표). LiDAR 를 고르면 LiDAR, 못 읽으면 nil.
    private var currentPerson: SIMD2<Float>? {
        useLiDAR ? tracker.personLiDAR : tracker.person
    }

    private func startWalk() {
        guard let target = tracker.target else { return }
        walking = true
        walkStart = Date()
        nearSince = nil
        startDistance = currentPerson.map { simd_distance($0, target) }
        beacon.startPings()
        loop = Task { @MainActor in
            while !Task.isCancelled {
                let now = Date()
                let tracking = tracker.isTracking(at: now)
                if tracking, let person = currentPerson {
                    lostNow = false
                    beacon.update(listener: person, source: target)
                    beacon.muted = false
                    let d = simd_distance(person, target)
                    if d <= 0.4 {
                        if nearSince == nil { nearSince = now }
                        if let since = nearSince, now.timeIntervalSince(since) >= 1.0 {
                            stopWalk(result: "도착")
                            return
                        }
                    } else {
                        nearSince = nil
                    }
                } else {
                    // 놓친 위치로 안내하지 않는다(R03). 소리를 끊고 기다린다.
                    lostNow = true
                    beacon.muted = true
                    nearSince = nil
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func stopWalk(result: String?) {
        loop?.cancel()
        loop = nil
        guard walking else { return }
        walking = false
        lostNow = false
        beacon.stopPings()
        guard let result else { return }
        let seconds = Date().timeIntervalSince(walkStart)
        let final = zip(currentPerson, tracker.target).map { simd_distance($0, $1) }
        if result == "도착" { beacon.announceArrival() }
        let text = String(format: "%@ · %.1f초 · 시작 거리 %@ · 끝 거리 %@",
                          result, seconds,
                          startDistance.map { String(format: "%.2fm", $0) } ?? "—",
                          final.map { String(format: "%.2fm", $0) } ?? "—")
        beacon.lastResult = text
        store.add(Trial(experiment: "S2",
                        condition: useLiDAR ? "LiDAR" : "사람 추적",
                        expected: "도착",
                        answered: result,
                        reactionMs: seconds * 1000,
                        note: text))
    }
}

private func zip(_ a: SIMD2<Float>?, _ b: SIMD2<Float>?) -> (SIMD2<Float>, SIMD2<Float>)? {
    guard let a, let b else { return nil }
    return (a, b)
}

/// S2 의 소리. 목표 자리에 ‘쏴’ 소리를 놓고, 청취자 = 카메라가 잡은 사람 위치 + AirPods 고개 방향.
/// 좌표는 폰 기준 바닥 좌표(x 오른쪽, y 앞)를 AVAudio3D(x 오른쪽, −z 앞)로 옮겨 쓴다.
/// 거리에 따라 소리가 작아진다(가까울수록 큼).
///
/// 고개 방향 부호는 2026-09-29 자동 확인(고개 오른쪽 → CMAttitude yaw 음수, 이때 왼쪽 음원이 앞에 옴)으로
/// 원래 부호 `-(yaw - offset)` 로 되돌린 것을 그대로 쓴다. ⚠️ 되돌린 뒤 실기기 확인은 아직이다.
@MainActor
final class StageBeaconAudio: ObservableObject {
    @Published private(set) var headReady = false
    @Published var lastResult: String?
    var muted = false

    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private let player = AVAudioPlayerNode()
    private let motion = CMHeadphoneMotionManager()
    private let speech = AVSpeechSynthesizer()
    private var ping: AVAudioPCMBuffer?
    private var headYaw: Double = 0
    private var yawOffset: Double = 0
    private var pingTask: Task<Void, Never>?

    func prepare() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
            ping = Self.makeNoise(format: format, seconds: 0.25)
            engine.attach(player)
            engine.attach(environment)
            engine.connect(player, to: environment, format: format)   // 모노여야 공간화된다
            engine.connect(environment, to: engine.mainMixerNode, format: nil)
            player.renderingAlgorithm = .HRTFHQ
            let att = environment.distanceAttenuationParameters
            att.distanceAttenuationModel = .inverse
            att.referenceDistance = 0.5
            att.maximumDistance = 8
            att.rolloffFactor = 1
            try engine.start()
            player.play()
        } catch {
            lastResult = "소리 준비 실패: \(error.localizedDescription)"
        }
        guard motion.isDeviceMotionAvailable else { return }
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.headYaw = data.attitude.yaw * 180 / .pi
            self.headReady = true
            // 정면을 맞출 때 무용수는 폰을 바라본다 = 카메라가 보는 쪽(−z)의 반대(+z). 그래서 180°를 더한다.
            self.environment.listenerAngularOrientation =
                AVAudio3DAngularOrientation(yaw: Float(-(self.headYaw - self.yawOffset) + 180), pitch: 0, roll: 0)
        }
    }

    /// 무용수가 폰(카메라)을 바라보고 있을 때 누른다. 무대에서 폰은 객석 쪽, 무용수는 객석을 보고 서므로 자연스럽다.
    func calibrate() { yawOffset = headYaw }

    /// 폰 기준 바닥 좌표(x 오른쪽, y 앞) → AVAudio3D(x 오른쪽, −z 앞)
    func update(listener: SIMD2<Float>, source: SIMD2<Float>) {
        environment.listenerPosition = AVAudio3DPoint(x: listener.x, y: 0, z: -listener.y)
        player.position = AVAudio3DPoint(x: source.x, y: 0, z: -source.y)
    }

    func startPings() {
        pingTask?.cancel()
        pingTask = Task { @MainActor in
            while !Task.isCancelled {
                if !muted, let ping { player.scheduleBuffer(ping, at: nil, options: [.interrupts], completionHandler: nil) }
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        }
    }

    func stopPings() {
        pingTask?.cancel()
        pingTask = nil
    }

    func announceArrival() {
        let u = AVSpeechUtterance(string: "도착")
        u.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        speech.speak(u)
    }

    func shutdown() {
        stopPings()
        motion.stopDeviceMotionUpdates()
        engine.stop()
    }

    private static func makeNoise(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let ch = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        let fade = Int(format.sampleRate * 0.01)
        var seed: UInt32 = 777
        for i in 0..<Int(frames) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            var v = Double(seed) / Double(UInt32.max) * 2 - 1
            if i < fade { v *= Double(i) / Double(fade) }
            if i > Int(frames) - fade { v *= Double(Int(frames) - i) / Double(fade) }
            ch[i] = Float(v * 0.5)
        }
        return buffer
    }
}
