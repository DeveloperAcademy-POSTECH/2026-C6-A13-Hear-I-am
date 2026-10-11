import CoreMotion
import Foundation
import WayDetectCore

/// Bounded mailbox: the sensor queue processes EVERY acceleration sample, while the UI
/// receives the latest attitude plus step timestamps. SwiftUI/disk work cannot backlog 50 Hz tasks.
private final class MotionMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var detector = StepDetector()
    private var latest: MotionObservation?
    private var steps: [Double] = []
    private var error: String?
    private var stillnessInterrupted = false
    func receive(_ data: CMDeviceMotion?, error: Error?, startUptime: Double) {
        lock.lock(); defer { lock.unlock() }
        if let error { self.error = error.localizedDescription }
        guard let data else { return }
        let matrix = data.attitude.rotationMatrix, a = data.userAcceleration, g = data.gravity, r = data.rotationRate
        let forward = Angles.heading(screenX: matrix.m31, screenY: matrix.m32, screenZ: matrix.m33)
        // Apple's frame contract: gravity_device = R * (0, 0, -1).
        // Record this invariant so a frame/conversion mismatch is detectable on the device.
        let gravityResidual = sqrt(pow(g.x + matrix.m13, 2) + pow(g.y + matrix.m23, 2) + pow(g.z + matrix.m33, 2))
        let magnitude = sqrt(g.x*g.x + g.y*g.y + g.z*g.z)
        let vertical = magnitude > 0.5 ? -(a.x*g.x + a.y*g.y + a.z*g.z) / magnitude : Double.nan
        let sample = MotionObservation(time: data.timestamp - startUptime, heading: forward.degrees,
            rotationRate: sqrt(r.x*r.x + r.y*r.y + r.z*r.z) * 180 / .pi,
            acceleration: sqrt(a.x*a.x + a.y*a.y + a.z*a.z), horizontalProjection: forward.projection,
            verticalAcceleration: vertical, gravityResidual: gravityResidual)
        latest = sample
        // Keep movement between UI polls: a later quiet sample must not hide it.
        if !sample.isValid || sample.rotationRate > 8 || sample.acceleration > 0.08 { stillnessInterrupted = true }
        steps.append(contentsOf: detector.receive(sample))
        if steps.count > 100 { steps.removeFirst(steps.count - 100); self.error = "화면 처리가 지연됐습니다. 위치를 확인하세요." }
    }
    func drain() -> (MotionObservation?, [Double], String?, Bool) {
        lock.lock(); defer { lock.unlock() }
        let result = (latest, steps, error, stillnessInterrupted)
        steps.removeAll(keepingCapacity: true); error = nil; stillnessInterrupted = false
        return result
    }
}

@MainActor
final class MotionService {
    private let motion = CMMotionManager()
    private let pedometer = CMPedometer()
    private let queue: OperationQueue = {
        let queue = OperationQueue(); queue.name = "WayDetect.motion"; queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated; return queue
    }()
    private var mailbox: MotionMailbox?
    private var generation = UUID()
    private var startUptime = 0.0
    private var sessionDate = Date()
    private var lastDelivered = -Double.infinity
    private var lastQuery = -Double.infinity
    private var queryID: UUID?
    private var queryStarted = 0.0
    private var counter = PedometerCounter()
    var onSamples: ((MotionObservation?, [Double], Double, Bool) -> Void)?
    var onSystemSteps: ((Int, String, Double) -> Void)?
    var onProblem: ((String) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    private var elapsed: Double { ProcessInfo.processInfo.systemUptime - startUptime }

    func prepareAccess(completion: @escaping (String?) -> Void) {
        guard motion.isDeviceMotionAvailable, CMPedometer.isStepCountingAvailable() else {
            completion("실기기에서 실행해 주세요. 방향·걸음 센서를 사용할 수 없습니다."); return
        }
        switch CMPedometer.authorizationStatus() {
        case .authorized: completion(nil)
        case .denied, .restricted: completion("iOS 설정 → 개인정보 보호 및 보안 → 동작 및 피트니스에서 WayDetect를 허용해 주세요.")
        case .notDetermined:
            let now = Date()
            pedometer.queryPedometerData(from: now.addingTimeInterval(-1), to: now) { _, _ in
                Task { @MainActor in
                    completion(CMPedometer.authorizationStatus() == .authorized ? nil : "동작 및 피트니스 접근을 허용해야 측정할 수 있습니다.")
                }
            }
        @unknown default: completion("동작 권한을 확인할 수 없습니다.")
        }
    }
    func start(uptime: Double, date: Date) {
        stop(); startUptime = uptime; sessionDate = date; lastDelivered = -.infinity
        lastQuery = elapsed; counter = PedometerCounter()
        let token = generation, box = MotionMailbox(); mailbox = box
        guard CMMotionManager.availableAttitudeReferenceFrames().contains(.xArbitraryZVertical) else {
            onProblem?("상대 방향 센서를 사용할 수 없습니다."); return
        }
        motion.deviceMotionUpdateInterval = 1.0 / 50
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { data, error in
            box.receive(data, error: error, startUptime: uptime)
        }
        // A single session-wide start, including turns and pauses. No route state can stop it.
        pedometer.startUpdates(from: date) { [weak self] data, error in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.accept(data, error: error, source: "실시간")
            }
        }
        onDiagnostic?("센서 시작 · 50 Hz 가속도 추정 + 세션 전체 iOS 누적 걸음")
    }
    func poll() {
        guard let mailbox else { return }
        let (sample, steps, error, stillnessInterrupted) = mailbox.drain()
        if let error { onProblem?(error) }
        var fresh: MotionObservation?
        if let sample, sample.time > lastDelivered { fresh = sample; lastDelivered = sample.time }
        onSamples?(fresh, steps, elapsed, stillnessInterrupted)
        pollPedometer()
    }
    private func pollPedometer() {
        if queryID != nil && elapsed - queryStarted > 8 {
            queryID = nil; onDiagnostic?("iOS 걸음 조회 응답 지연 · 실시간 추정은 계속됩니다.")
        }
        guard queryID == nil, elapsed - lastQuery >= 2 else { return }
        let token = generation, request = UUID(); queryID = request; lastQuery = elapsed; queryStarted = elapsed
        pedometer.queryPedometerData(from: sessionDate, to: Date()) { [weak self] data, error in
            Task { @MainActor in
                guard let self, self.generation == token, self.queryID == request else { return }
                self.queryID = nil; self.accept(data, error: error, source: "보완 조회")
            }
        }
    }
    private func accept(_ data: CMPedometerData?, error: Error?, source: String) {
        if let error {
            onDiagnostic?("iOS 걸음 \(source) 오류: \(error.localizedDescription)")
            if CMPedometer.authorizationStatus() != .authorized { onProblem?("동작 및 피트니스 권한을 확인하세요.") }
            return
        }
        guard let data else { return }
        let count = data.numberOfSteps.intValue
        guard counter.merge(count) else {
            onDiagnostic?("이전 iOS 누적값 \(count) 제외 · 현재 \(counter.total)"); return
        }
        onSystemSteps?(counter.total, source, elapsed)
    }
    func stop() {
        generation = UUID(); queryID = nil; mailbox = nil
        motion.stopDeviceMotionUpdates(); pedometer.stopUpdates()
    }
}
