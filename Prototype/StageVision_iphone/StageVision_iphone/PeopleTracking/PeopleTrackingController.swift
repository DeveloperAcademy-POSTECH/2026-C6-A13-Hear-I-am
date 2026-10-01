import ARKit
import AVFoundation
import Combine
import ImageIO
import QuartzCore
import UIKit
import Vision

nonisolated struct PeopleFrame: Sendable {
    var people: [TrackedPerson] = []
    var camera = matrix_identity_float4x4
    var status: String
    var rejected = 0
    var requiresRestart = false
    var timestamp: TimeInterval = 0
    var personVisible = false
}

/// All Vision, depth reads, and identity association stay on one serial delegate queue.
nonisolated final class PeopleFrameProcessor: NSObject, ARSessionDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "stagevision.people", qos: .userInitiated)
    var deliver: (@Sendable (PeopleFrame) -> Void)?
    private var orientation: CGImagePropertyOrientation = .right
    private var turns = 1
    private var lastFrame: TimeInterval = -1
    private var tracker = PersonTracker()
    private let singlePersonMode: Bool
    private let singleTracker = SinglePersonVisionTracker()
    init(singlePersonMode: Bool = false) { self.singlePersonMode = singlePersonMode; super.init() }
    func setPersonSelected(_ value: Bool) {
        queue.async { self.singleTracker.selected = value }
    }

    func setOrientation(_ value: CGImagePropertyOrientation, turns: Int) {
        queue.async { self.orientation = value; self.turns = turns }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        process(frame)
    }

    func process(_ frame: ARFrame) {
        guard CACurrentMediaTime() - frame.timestamp < 0.3 else { return }
        guard frame.timestamp - lastFrame >= 0.12 else { return }
        lastFrame = frame.timestamp
        if singlePersonMode {
            deliver?(singleTracker.process(frame, orientation: orientation, turns: turns))
            return
        }
        guard case .normal = frame.camera.trackingState else {
            tracker = PersonTracker()
            deliver?(PeopleFrame(status: "공간 추적 준비 중 · 주변을 천천히 비춰주세요"))
            return
        }
        guard PeopleTrackingMath.relative(.zero, camera: frame.camera.transform) != nil else {
            deliver?(PeopleFrame(status: "휴대폰을 수평 전방으로 향해주세요"))
            return
        }
        guard let depth = frame.sceneDepth, let confidence = depth.confidenceMap,
              let mask = frame.segmentationBuffer else {
            deliver?(PeopleFrame(status: "LiDAR 깊이와 사람 영역을 준비하고 있습니다"))
            return
        }
        let request = VNDetectHumanBodyPoseRequest()
        do {
            try VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: orientation).perform([request])
            let observations = request.results ?? []
            let buffer = depth.depthMap
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            CVPixelBufferLockBaseAddress(confidence, .readOnly)
            CVPixelBufferLockBaseAddress(mask, .readOnly)
            defer {
                CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
                CVPixelBufferUnlockBaseAddress(confidence, .readOnly)
                CVPixelBufferUnlockBaseAddress(mask, .readOnly)
            }
            var measurements: [PersonMeasurement] = []
            for observation in observations {
                guard let points = try? observation.recognizedPoints(.all),
                      let root = points[.root], root.confidence > 0.45,
                      let neck = points[.neck], neck.confidence > 0.45 else { continue }
                // An interior torso point avoids arm/leg boundaries and clothing edges.
                let center = SIMD2(Float((root.location.x + neck.location.x) / 2),
                                   Float((root.location.y + neck.location.y) / 2))
                let uv = PeopleTrackingMath.sensorPoint(center, quarterTurns: turns)
                guard let sample = sampleDepth(uv, depth: buffer, confidence: confidence, mask: mask) else { continue }
                let resolution = frame.camera.imageResolution
                let pixel = uv * SIMD2(Float(resolution.width), Float(resolution.height))
                let position = PeopleTrackingMath.worldPoint(pixel: pixel, depth: sample.depth,
                    intrinsics: frame.camera.intrinsics, camera: frame.camera.transform)
                measurements.append(PersonMeasurement(position: position, depthSpread: sample.spread))
            }
            guard CACurrentMediaTime() - frame.timestamp < 0.7 else {
                deliver?(PeopleFrame(status: "처리 지연 · 오래된 측정값을 제외했습니다"))
                return
            }
            let people = tracker.update(measurements, time: frame.timestamp)
            deliver?(PeopleFrame(people: people, camera: frame.camera.transform,
                                 status: "LiDAR 실시간 측정", rejected: observations.count - measurements.count, timestamp: frame.timestamp))
        } catch {
            tracker = PersonTracker()
            deliver?(PeopleFrame(status: "사람 인식 처리 실패 · 다시 시작해주세요", requiresRestart: true))
        }
    }

    private func sampleDepth(_ uv: SIMD2<Float>, depth: CVPixelBuffer,
                             confidence: CVPixelBuffer, mask: CVPixelBuffer) -> (depth: Float, spread: Float)? {
        guard uv.x > 0, uv.x < 1, uv.y > 0, uv.y < 1,
              let dBase = CVPixelBufferGetBaseAddress(depth),
              let cBase = CVPixelBufferGetBaseAddress(confidence),
              let mBase = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let width = CVPixelBufferGetWidth(depth), height = CVPixelBufferGetHeight(depth)
        guard CVPixelBufferGetWidth(confidence) == width, CVPixelBufferGetHeight(confidence) == height else { return nil }
        let mw = CVPixelBufferGetWidth(mask), mh = CVPixelBufferGetHeight(mask)
        let x = Int(uv.x * Float(width)), y = Int(uv.y * Float(height))
        var values: [Float] = []
        for dy in -2...2 {
            for dx in -2...2 {
                let px = x + dx, py = y + dy
                guard px >= 0, px < width, py >= 0, py < height else { continue }
                let confidenceValue = cBase.advanced(by: py * CVPixelBufferGetBytesPerRow(confidence)).assumingMemoryBound(to: UInt8.self)[px]
                guard confidenceValue == ARConfidenceLevel.high.rawValue else { continue }
                let mx = min(mw - 1, px * mw / width), my = min(mh - 1, py * mh / height)
                let person = mBase.advanced(by: my * CVPixelBufferGetBytesPerRow(mask)).assumingMemoryBound(to: UInt8.self)[mx]
                guard person > 127 else { continue }
                values.append(dBase.advanced(by: py * CVPixelBufferGetBytesPerRow(depth)).assumingMemoryBound(to: Float32.self)[px])
            }
        }
        return PeopleTrackingMath.robustDepth(values)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        tracker = PersonTracker()
        deliver?(PeopleFrame(status: "센서가 중단되었습니다 · 다시 시작해주세요", requiresRestart: true))
    }
    func sessionInterruptionEnded(_ session: ARSession) {
        tracker = PersonTracker()
        deliver?(PeopleFrame(status: "센서 중단 종료 · 다시 시작해주세요", requiresRestart: true))
    }
    func session(_ session: ARSession, didFailWithError error: Error) {
        deliver?(PeopleFrame(status: "센서 오류 · 다시 시작해주세요", requiresRestart: true))
    }
}

@MainActor
final class PeopleTrackingController: ObservableObject {
    enum Mode: String, CaseIterable { case live = "LiDAR 실측", demo = "시뮬레이션" }
    static let semantics: ARConfiguration.FrameSemantics = [.sceneDepth, .personSegmentation]
    let supported = ARWorldTrackingConfiguration.isSupported && ARWorldTrackingConfiguration.supportsFrameSemantics(semantics)
    @Published var mode: Mode = .live
    @Published var range: Double = 4
    @Published private(set) var people: [TrackedPerson] = []
    @Published private(set) var camera = matrix_identity_float4x4
    @Published private(set) var status = "시작을 눌러 사람 감지를 켜세요"
    @Published private(set) var running = false
    @Published private(set) var rejected = 0
    @Published private(set) var permissionDenied = false
    private var session: ARSession?
    private var processor: PeopleFrameProcessor?
    private var ticker: Timer?
    private var generation = UUID()
    private var lastResult = Date.distantPast
    private var demoStart = Date()

    var visiblePeople: [TrackedPerson] {
        people.filter {
            guard let p = relative($0) else { return false }
            return p.z > 0 && simd_length(p) <= Float(range)
        }.sorted { $0.id < $1.id }
    }
    func relative(_ person: TrackedPerson) -> SIMD3<Float>? {
        PeopleTrackingMath.relative(person.position, camera: camera)
    }
    func appear() {
        if !supported { mode = .demo; start() }
    }
    func changeMode() {
        stop()
        status = mode == .demo ? "가상 인물 예제 · 시작을 눌러 재생" : "시작을 눌러 사람 감지를 켜세요"
        if mode == .demo { start() }
    }
    func start() {
        stop()
        let token = generation
        if mode == .demo {
            running = true
            demoStart = Date()
            status = "시뮬레이션 · 실제 측정값이 아닙니다"
            tick()
            startTimer()
            return
        }
        guard supported else { status = "LiDAR 지원 기기가 필요합니다 · 시뮬레이션을 이용하세요"; return }
        status = "카메라 권한 및 센서 준비 중"
        Task { [weak self] in
            let allowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
                ? true : await AVCaptureDevice.requestAccess(for: .video)
            guard let self, self.generation == token else { return }
            self.permissionDenied = !allowed
            guard allowed else { self.status = "설정에서 카메라 접근을 허용해주세요"; return }
            let processor = PeopleFrameProcessor()
            processor.deliver = { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token, self.running else { return }
                    if result.requiresRestart {
                        self.stop()
                        self.status = result.status
                        return
                    }
                    self.people = result.people
                    self.camera = result.camera
                    self.status = result.status
                    self.rejected = result.rejected
                    self.lastResult = Date()
                }
            }
            let session = ARSession()
            session.delegate = processor
            session.delegateQueue = processor.queue
            self.processor = processor
            self.session = session
            self.updateOrientation()
            let config = ARWorldTrackingConfiguration()
            config.frameSemantics = Self.semantics
            config.worldAlignment = .gravity
            session.run(config, options: [.resetTracking, .removeExistingAnchors])
            self.running = true
            self.lastResult = Date()
            self.startTimer()
        }
    }
    func stop() {
        generation = UUID()
        ticker?.invalidate(); ticker = nil
        session?.pause(); session?.delegate = nil
        session = nil; processor = nil
        people = []; rejected = 0; running = false
        camera = matrix_identity_float4x4
        status = "일시 정지 · 시작하면 새로 감지합니다"
    }
    private func startTimer() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }
    private func updateOrientation() {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        switch scene?.effectiveGeometry.interfaceOrientation {
        case .landscapeLeft: processor?.setOrientation(.down, turns: 2)
        case .landscapeRight: processor?.setOrientation(.up, turns: 0)
        case .portraitUpsideDown: processor?.setOrientation(.left, turns: 3)
        default: processor?.setOrientation(.right, turns: 1)
        }
    }
    private func tick() {
        guard running else { return }
        if mode == .live {
            updateOrientation()
            if Date().timeIntervalSince(lastResult) > 1 {
                people = []
                status = "센서 응답 대기 중 · 계속되면 다시 시작해주세요"
            }
            return
        }
        let t = Float(Date().timeIntervalSince(demoStart))
        let positions: [SIMD3<Float>] = [SIMD3(-0.9, -0.35, -2.3),
            SIMD3(0.8 + sin(t * 0.6) * 0.65, -0.25, -3.1),
            SIMD3(-0.2 + sin(t * 0.4) * 0.4, -0.3, -4.45 + cos(t * 0.4) * 0.2)]
        people = positions.enumerated().map { i, p in
            let speed: Float = i == 0 ? 0 : (i == 1 ? abs(cos(t * 0.6) * 0.39) : sqrt(pow(cos(t * 0.4) * 0.16, 2) + pow(sin(t * 0.4) * 0.08, 2)))
            return TrackedPerson(id: i + 1, position: p, lastSeen: Double(t), depthSpread: 0,
                                 speed: speed, moving: speed > 0.14, motionOrigin: p, motionTime: 0, motionReady: true)
        }
    }
}
