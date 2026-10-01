import ARKit
import SceneKit
import AVFoundation
import Combine
import UIKit
import RoomPlan
import ImageIO

@MainActor
final class StageScanController: NSObject, ObservableObject, ARSessionDelegate {
    @Published var guide = GuidanceState() {
        didSet {
            if (guide.selectedID != nil) != (oldValue.selectedID != nil) {
                peopleProcessor?.setPersonSelected(guide.selectedID != nil)
            }
        }
    }
    @Published private(set) var guidanceMap: StageMap?
    var enablesGuidance = false
    var supportsGuidance: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(PeopleTrackingController.semantics)
    }
    private var peopleProcessor: PeopleFrameProcessor?
    private var processingPeople = false
    private var guidanceGeneration = UUID()

    enum Phase { case floor, origin, front, boundary }
    @Published private(set) var phase: Phase = .floor
    @Published private(set) var tracking = "카메라 준비 중"
    @Published private(set) var normalTracking = false
    @Published private(set) var hasCandidate = false
    @Published private(set) var hasAim = false
    @Published private(set) var aimDescription = "바닥을 천천히 비추세요."
    @Published private(set) var pointCount = 0
    @Published private(set) var candidateDescription = "수평 바닥을 찾고 있습니다."
    @Published var error: String?
    @Published private(set) var needsRestart = false
    let capabilities = "ARKit \(ARWorldTrackingConfiguration.isSupported ? "지원" : "미지원") · LiDAR \(ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) ? "지원" : "없음") · RoomPlan \(RoomCaptureSession.isSupported ? "지원" : "없음")"
    weak var view: ARSCNView?
    private var displayLink: CADisplayLink?
    private var candidate: ARPlaneAnchor?
    private var selectedCandidateID: UUID?
    private var candidates: [ARPlaneAnchor] = []
    private var floorHeight: Float?
    private var origin: SIMD3<Float>?
    private var stageFrame: StageFrame?
    private var aim: SIMD3<Float>?
    private var aimVirtual = false
    private var worldPoints: [SIMD3<Float>] = []
    private var virtualPoints: [Int] = []
    private var interruptionCount = 0
    private var lastNormal = false
    private var running = false
    private let boundaryNode = SCNNode()
    private let floorNode = SCNNode()
    private let aimNode = SCNNode()

    func attach(_ view: ARSCNView) {
        self.view = view
        view.scene = SCNScene()
        view.scene.rootNode.addChildNode(boundaryNode)
        view.scene.rootNode.addChildNode(floorNode)
        view.scene.rootNode.addChildNode(aimNode)
        view.session.delegate = self
        view.session.delegateQueue = .main
        view.automaticallyUpdatesLighting = false
        Task { [weak self] in
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
            default: allowed = false
            }
            guard let self, self.view != nil else { return }
            guard allowed else { self.error = "카메라 권한이 없습니다. 설정 앱에서 StageVision의 카메라를 허용하세요."; return }
            self.run()
        }
    }
    private func run() {
        guard ARWorldTrackingConfiguration.isSupported else { error = "이 기기는 ARKit 무대 스캔을 지원하지 않습니다."; return }
        let config = ARWorldTrackingConfiguration()
        if enablesGuidance && supportsGuidance {
            config.frameSemantics = PeopleTrackingController.semantics
        }
        config.planeDetection = [.horizontal]
        config.worldAlignment = .gravity
        view?.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        running = true
        displayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(refresh))
        link.preferredFramesPerSecond = 20
        link.add(to: .main, forMode: .common)
        displayLink = link
    }
    func stop() {
        endGuidance()
        running = false
        displayLink?.invalidate(); displayLink = nil
        view?.session.pause()
        view?.session.delegate = nil
        view = nil
    }
    func reset() {
        endGuidance()
        phase = .floor; worldPoints = []; virtualPoints = []; pointCount = 0
        origin = nil; stageFrame = nil; floorHeight = nil; candidate = nil; candidates = []
        selectedCandidateID = nil; aim = nil; hasAim = false; hasCandidate = false
        normalTracking = false; lastNormal = false; needsRestart = false; error = nil
        interruptionCount = 0
        boundaryNode.childNodes.forEach { $0.removeFromParentNode() }
        floorNode.childNodes.forEach { $0.removeFromParentNode() }
        aimNode.childNodes.forEach { $0.removeFromParentNode() }
        // Restore delegate in case a session failure occurred.
        view?.session.delegate = self
        run()
    }
    func nextFloor() {
        guard phase == .floor, !candidates.isEmpty else { return }
        let index = candidates.firstIndex { $0.identifier == candidate?.identifier } ?? 0
        selectedCandidateID = candidates[(index + 1) % candidates.count].identifier
        refresh()
    }
    @objc private func refresh() {
        guard running, let view, let frame = view.session.currentFrame else { return }
        let isFresh = ProcessInfo.processInfo.systemUptime - frame.timestamp < 0.5
        let isNormal: Bool
        switch frame.camera.trackingState {
        case .normal: isNormal = isFresh && !needsRestart; tracking = needsRestart ? "세션 중단: 전체 초기화가 필요합니다." : "추적 정상"
        case .notAvailable: isNormal = false; tracking = "추적 불가"
        case .limited(let reason):
            isNormal = false
            switch reason {
            case .excessiveMotion: tracking = "기기를 더 천천히 움직이세요."
            case .insufficientFeatures: tracking = "조명을 밝히고 무늬가 있는 바닥을 비추세요."
            case .relocalizing: tracking = "공간을 다시 찾는 중입니다."
            default: tracking = "바닥을 천천히 비추며 추적을 준비하세요."
            }
        }
        if !isFresh { tracking = "카메라 프레임 대기 중" }
        if lastNormal && !isNormal { interruptionCount += 1 }
        lastNormal = isNormal; normalTracking = isNormal
        if phase == .floor {
            candidates = frame.anchors.compactMap { $0 as? ARPlaneAnchor }.filter {
                $0.alignment == .horizontal && $0.transform.columns.3.y < frame.camera.transform.columns.3.y - 0.15
                    && $0.planeExtent.width * $0.planeExtent.height >= 0.2
            }.sorted { $0.planeExtent.width * $0.planeExtent.height > $1.planeExtent.width * $1.planeExtent.height }
            candidate = candidates.first { $0.identifier == selectedCandidateID } ?? candidates.first
            hasCandidate = candidate != nil
            drawFloor()
        }
        if guidanceMap != nil {
            guide.expire(time: ProcessInfo.processInfo.systemUptime)
            if !normalTracking { guide.waitForPosition("공간 추적 안정화 대기 · P 선택 유지") }
            return
        }
        updateAim(frame: frame)
    }
    private func updateAim(frame: ARFrame) {
        aim = nil; hasAim = false
        aimNode.childNodes.forEach { $0.removeFromParentNode() }
        guard normalTracking, let view, let height = floorHeight,
              view.bounds.width > 0, view.bounds.height > 0,
              let query = view.raycastQuery(from: CGPoint(x: view.bounds.midX, y: view.bounds.midY), allowing: .existingPlaneGeometry, alignment: .horizontal)
        else { aimDescription = phase == .floor ? "민트색 바닥 후보가 무대 바닥인지 확인하세요." : "추적이 안정될 때까지 기다리세요."; return }
        // Reject hits on the audience floor, a platform, or props at another height.
        let hit = view.session.raycast(query).first {
            abs($0.worldTransform.columns.3.y - height) < 0.08
                && simd_distance(SIMD3($0.worldTransform.columns.3.x, $0.worldTransform.columns.3.y, $0.worldTransform.columns.3.z), query.origin) <= 20
        }
        if let hit {
            aim = SIMD3(hit.worldTransform.columns.3.x, height, hit.worldTransform.columns.3.z)
            aimVirtual = false
        } else {
            aim = StageFrame.floorIntersection(origin: query.origin, direction: simd_normalize(query.direction), height: height)
            aimVirtual = true
        }
        hasAim = aim != nil
        if let aim {
            aimDescription = aimVirtual ? "가상 바닥 교차 · 높이는 확정값 사용" : "검출 바닥 raycast"
            if let first = worldPoints.first {
                aimDescription += String(format: " · 시작점까지 %.2fm", simd_distance(first, aim))
            }
            aimNode.addChildNode(dot(aim, color: aimVirtual ? .systemOrange : .systemMint, radius: 0.025))
            if let last = worldPoints.last { aimNode.addChildNode(line(last, aim, color: .white, radius: 0.006)) }
        } else { aimDescription = "바닥 쪽으로 내려 비추세요. 수평 광선·20m 초과 입력은 차단됩니다." }
    }
    func confirmFloor() {
        refresh()
        guard normalTracking, let candidate else { return }
        floorHeight = candidate.transform.columns.3.y
        phase = .origin
        floorNode.childNodes.forEach { $0.removeFromParentNode() }
    }
    func confirmOrigin() {
        refresh()
        guard normalTracking, let aim else { return }
        origin = aim; phase = .front
    }
    func confirmFront() {
        refresh()
        guard normalTracking, let origin, let camera = view?.session.currentFrame?.camera else { return }
        let column = camera.transform.columns.2
        guard let frame = StageFrame(origin: origin, cameraForward: -SIMD3(column.x, column.y, column.z)) else {
            error = "기기를 너무 수직으로 들고 있습니다. 객석 방향으로 조금 더 수평하게 향하세요."; return
        }
        stageFrame = frame; phase = .boundary
    }
    func addPoint() {
        refresh()
        guard normalTracking, let aim, let stageFrame, phase == .boundary else { return }
        guard worldPoints.count < StageGeometry.maximumPoints else { error = "경계점은 최대 128개입니다."; return }
        let point = stageFrame.point(aim)
        if worldPoints.contains(where: { (stageFrame.point($0) - point).length < StageGeometry.minimumSpacing }) {
            error = "기존 점에서 5cm 이상 떨어진 위치를 지정하세요. 시작점을 다시 찍지 말고 경계 닫기를 누르세요."; return
        }
        if worldPoints.count >= 3 {
            let points = worldPoints.map(stageFrame.point)
            for i in 0..<(points.count - 2) {
                if StageGeometry.intersects(points[i], points[i + 1], points.last!, point) {
                    error = "새 선분이 기존 경계와 교차합니다. 위치를 다시 조준하세요."; return
                }
            }
        }
        if aimVirtual { virtualPoints.append(worldPoints.count) }
        worldPoints.append(aim); pointCount = worldPoints.count
        drawBoundary(closed: false)
    }
    func undo() {
        guard !worldPoints.isEmpty else { return }
        worldPoints.removeLast(); virtualPoints.removeAll { $0 >= worldPoints.count }
        pointCount = worldPoints.count; drawBoundary(closed: false)
    }
    func finish(name: String, venue: String) -> StageMap? {
        refresh()
        guard normalTracking, let stageFrame else { error = "추적이 정상인 상태에서 경계를 닫아주세요."; return nil }
        let points = worldPoints.map(stageFrame.point)
        if let issue = StageGeometry.validate(points) { error = issue.message; return nil }
        var map = StageMap(points: points)
        map.name = name.isEmpty ? "새 무대" : name; map.venue = venue
        map.coordinateSystem.stageToARWorld = stageFrame.matrix
        map.quality.virtualPlanePointIndexes = virtualPoints
        map.quality.unverifiedSegmentIndexes = points.indices.filter {
            virtualPoints.contains($0) || virtualPoints.contains(($0 + 1) % points.count)
                || (points[$0] - points[($0 + 1) % points.count]).length > 5
        }
        map.quality.trackingInterruptionCount = interruptionCount
        map.rebuildRiskZones()
        drawBoundary(closed: true)
        return map
    }
    func beginGuidance(map: StageMap) {
        guard supportsGuidance, running, stageFrame != nil else {
            error = "실시간 P 추적에는 LiDAR sceneDepth·사람 분할 지원 기기가 필요합니다."; return
        }
        guidanceGeneration = UUID()
        let token = guidanceGeneration
        guide = GuidanceState(polygon: map.floorPolygon, usesHeadTracking: true)
        guidanceMap = map
        aimNode.childNodes.forEach { $0.removeFromParentNode() }
        let processor = PeopleFrameProcessor(singlePersonMode: true)
        processor.deliver = { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.guidanceGeneration == token, self.running,
                      !self.needsRestart, let stageFrame = self.stageFrame else { return }
                if result.requiresRestart { self.invalidateSession(result.status); return }
                guard self.normalTracking else { self.guide.waitForPosition("공간 추적 불안정 · P 선택 유지"); return }
                guard ProcessInfo.processInfo.systemUptime - result.timestamp <= 0.5 else {
                    self.guide.waitForPosition("측정 지연 · P 선택 유지"); return
                }
                self.guide.receive(result.people.map { GuidePerson(id: $0.id, point: stageFrame.point($0.position)) },
                                   time: result.timestamp, visualContact: result.personVisible, detail: result.status)
            }
        }
        peopleProcessor = processor
    }
    private func endGuidance() {
        guidanceGeneration = UUID(); peopleProcessor = nil; processingPeople = false
        guidanceMap = nil; guide = GuidanceState()
    }
    // Forward the SAME ARSession's frames; keep Vision work off the main queue.
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor [weak self] in
            guard let self, self.running, !self.needsRestart, self.normalTracking,
                  !self.processingPeople, let processor = self.peopleProcessor else { return }
            self.processingPeople = true
            let token = self.guidanceGeneration
            let orientation = self.view?.window?.windowScene?.effectiveGeometry.interfaceOrientation
            switch orientation {
            case .landscapeLeft: processor.setOrientation(.down, turns: 2)
            case .landscapeRight: processor.setOrientation(.up, turns: 0)
            case .portraitUpsideDown: processor.setOrientation(.left, turns: 3)
            default: processor.setOrientation(.right, turns: 1)
            }
            processor.queue.async {
                processor.process(frame)
                Task { @MainActor [weak self] in
                    guard let self, self.guidanceGeneration == token else { return }
                    self.processingPeople = false
                }
            }
        }
    }
    private func drawFloor() {
        floorNode.childNodes.forEach { $0.removeFromParentNode() }
        guard let candidate else { return }
        let extent = candidate.planeExtent
        candidateDescription = String(format: "바닥 후보 %d개 · 선택 %.1f × %.1fm", candidates.count, extent.width, extent.height)
        // Actual detected boundary, rather than a potentially oversized extent rectangle.
        let vertices = candidate.geometry.boundaryVertices
        guard vertices.count >= 3 else { return }
        let world = vertices.map { p -> SIMD3<Float> in
            let q = candidate.transform * SIMD4(p.x, p.y, p.z, 1)
            return SIMD3(q.x, q.y + 0.005, q.z)
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: world.map { SCNVector3($0.x, $0.y, $0.z) })],
                                   elements: [SCNGeometryElement(indices: (1..<(world.count - 1)).flatMap { [Int32(0), Int32($0), Int32($0 + 1)] }, primitiveType: .triangles)])
        geometry.firstMaterial = material(.systemMint.withAlphaComponent(0.2))
        floorNode.addChildNode(SCNNode(geometry: geometry))
        for i in world.indices { floorNode.addChildNode(line(world[i], world[(i + 1) % world.count], color: .systemMint, radius: 0.008)) }
    }
    private func drawBoundary(closed: Bool) {
        boundaryNode.childNodes.forEach { $0.removeFromParentNode() }
        for i in worldPoints.indices {
            boundaryNode.addChildNode(dot(worldPoints[i], color: i == 0 ? .systemMint : .systemOrange, radius: 0.04))
            if i > 0 { boundaryNode.addChildNode(line(worldPoints[i - 1], worldPoints[i], color: .systemOrange, radius: 0.012)) }
        }
        if closed, let first = worldPoints.first, let last = worldPoints.last { boundaryNode.addChildNode(line(last, first, color: .systemOrange, radius: 0.012)) }
    }
    private func material(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial(); m.diffuse.contents = color; m.lightingModel = .constant; m.isDoubleSided = true
        return m
    }
    private func dot(_ p: SIMD3<Float>, color: UIColor, radius: CGFloat) -> SCNNode {
        let sphere = SCNSphere(radius: radius); sphere.firstMaterial = material(color)
        let node = SCNNode(geometry: sphere); node.simdPosition = p
        return node
    }
    private func line(_ a: SIMD3<Float>, _ b: SIMD3<Float>, color: UIColor, radius: CGFloat) -> SCNNode {
        let delta = b - a, length = simd_length(delta)
        guard length > 0.0001 else { return SCNNode() }
        let cylinder = SCNCylinder(radius: radius, height: CGFloat(length)); cylinder.firstMaterial = material(color)
        let node = SCNNode(geometry: cylinder)
        node.simdPosition = (a + b) / 2
        node.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: delta / length)
        return node
    }
    // A session interruption invalidates continued capture in this MVP; don't silently mix frames.
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in self?.invalidateSession("스캔이 중단되었습니다. 좌표 정합을 보장할 수 없어 전체 초기화 후 다시 스캔해야 합니다.") }
    }
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.invalidateSession(message) }
    }
    func invalidateSession(_ message: String) {
        guard running else { return }
        guide.invalidate("세션 중단 · 다시 스캔해주세요.")
        needsRestart = true; normalTracking = false; hasAim = false; aim = nil
        error = message
    }
}
