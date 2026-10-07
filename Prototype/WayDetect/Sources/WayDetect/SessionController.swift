import AVFoundation
import Combine
import UIKit
import WayDetectCore

@MainActor
final class SessionController: ObservableObject {
    @Published private(set) var engine: NavigationEngine?
    @Published private(set) var latestResult: SessionRecord?
    @Published private(set) var resultSaved = false
    @Published private(set) var isPreparing = false
    @Published private(set) var elapsed = 0.0
    @Published private(set) var systemStatus = "iOS 걸음 응답 대기"
    @Published private(set) var lastGuidanceText = ""
    @Published var startError: String?
    private let motion = MotionService()
    private let guidance = GuidanceService()
    private var timer: Timer?
    private var startUptime = 0.0
    private var processedEvents = 0
    private var lastSave = 0.0
    private var demoHeading = 0.0
    private var demoSignal = true
    private var previousDemoHeading = 0.0
    private var previousDemoTime = 0.0
    private var pendingRoute: Route?
    private weak var store: AppStore?
    private var interruption: AnyCancellable?
    var isActive: Bool { engine.map { !$0.phase.isFinished } ?? false }
    var isDemo: Bool { engine?.record.isDemo ?? false }
    var needsResultDecision: Bool { latestResult != nil && !resultSaved }

    init() {
        motion.onSamples = { [weak self] sample, steps, time, stillnessInterrupted in
            guard let self else { return }
            self.engine?.receiveBatch(sample, estimatedSteps: steps, at: time, stillnessInterrupted: stillnessInterrupted)
        }
        motion.onSystemSteps = { [weak self] count, source, time in
            guard let self else { return }
            self.systemStatus = "\(source) 응답 · \(Int(time))초"
            self.engine?.receiveSystemSteps(count, at: time, source: source)
        }
        motion.onDiagnostic = { [weak self] message in self?.engine?.diagnostic(message) }
        motion.onProblem = { [weak self] message in self?.pause(message) }
        guidance.onFailure = { [weak self] reason in
            guard let self else { return }
            self.engine?.pause(reason)
            // No recursive attempt to speak an audio failure.
            self.processedEvents = self.engine?.record.events.count ?? 0
            self.persist()
        }
        interruption = NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: RunLoop.main).sink { [weak self] note in
                guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      type == AVAudioSession.InterruptionType.began.rawValue else { return }
                self?.pause("음성이 중단됐습니다. 멈춰서 안내가 들리는지 확인하세요.")
            }
    }
    func start(route: Route, demo: Bool, store: AppStore) {
        guard !isActive, latestResult == nil, !isPreparing, store.interruptedRecord == nil, route.validationMessage == nil else { return }
        self.store = store; startError = nil
        if demo { begin(route, demo: true); return }
        isPreparing = true
        // Complete the iOS permission interaction BEFORE creating a route session.
        motion.prepareAccess { [weak self] error in
            guard let self else { return }
            if let error { self.isPreparing = false; self.startError = error; return }
            self.pendingRoute = route; self.startPreparedIfActive()
        }
    }
    private func startPreparedIfActive() {
        guard UIApplication.shared.applicationState == .active, let route = pendingRoute else { return }
        pendingRoute = nil; isPreparing = false; begin(route, demo: false)
    }
    private func begin(_ route: Route, demo: Bool) {
        guidance.stop(); motion.stop(); timer?.invalidate()
        latestResult = nil; resultSaved = false; processedEvents = 0; elapsed = 0; lastSave = 0; lastGuidanceText = ""
        demoHeading = 0; previousDemoHeading = 0; previousDemoTime = 0; demoSignal = true
        startUptime = ProcessInfo.processInfo.systemUptime
        let date = Date()
        engine = NavigationEngine(route: route, settings: store?.settings ?? .init(), isDemo: demo, date: date)
        if let build = Bundle.main.object(forInfoDictionaryKey: "WayDetectBuildIdentifier") as? String {
            engine?.diagnostic("앱 빌드 " + build)
        }
        systemStatus = demo ? "시뮬레이션 입력" : "iOS 걸음 응답 대기"
        UIApplication.shared.isIdleTimerDisabled = true
        if !demo { motion.start(uptime: startUptime, date: date) }
        timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        handleChanges(); persist()
    }
    private func tick() {
        guard isActive else { return }
        elapsed = ProcessInfo.processInfo.systemUptime - startUptime
        if isDemo {
            if demoSignal {
                let dt = max(0.01, elapsed - previousDemoTime)
                let rate = abs(Angles.signed(demoHeading - previousDemoHeading)) / dt
                engine?.receive(MotionObservation(time: elapsed, heading: demoHeading, rotationRate: rate), at: elapsed)
                previousDemoHeading = demoHeading; previousDemoTime = elapsed
            }
        } else { motion.poll() }
        engine?.tick(at: elapsed); handleChanges()
        if elapsed - lastSave >= 3 { persist(); lastSave = elapsed }
    }
    func setReference() { _ = engine?.setInitialReference(); changed() }
    func beginWalking() { _ = engine?.beginWalking(); changed() }
    func resetDirection() { engine?.requestDirectionReset(); changed() }
    func restartFromSpot() { engine?.restartFromConfirmedSpot(); changed() }
    func resume(remaining: Int) { _ = engine?.resume(remainingSteps: remaining); changed() }
    func repeatInstruction() { engine?.repeatInstruction(); handleChanges() }
    func pause(_ reason: String = "위치와 남은 걸음을 확인한 뒤 계속하세요.") {
        guard isActive else { return }; engine?.pause(reason); changed()
    }
    func finish() { engine?.finish(); changed() }
    func demoTurn(_ offset: Double) { guard isDemo else { return }; demoHeading += offset }
    func demoStep() {
        guard isDemo, isActive else { return }
        engine?.receiveEstimatedSteps([elapsed], at: elapsed); handleChanges()
    }
    func toggleDemoSignal() { demoSignal.toggle() }
    func enteredBackground() {
        guard isActive else { return }
        engine?.sensorStreamRestarted(); handleChanges()
        motion.stop(); guidance.stop(); persist()
    }
    func becameActive(resumeSensors: Bool) {
        startPreparedIfActive()
        guard resumeSensors, isActive, !isDemo, let engine else { return }
        motion.start(uptime: startUptime, date: engine.record.startedAt)
    }
    func saveResult() {
        guard needsResultDecision, let latestResult, store?.saveSession(latestResult) == true else { return }
        resultSaved = true
    }
    func discardResult() {
        guard needsResultDecision, let latestResult, store?.discardPendingSession(id: latestResult.id) == true else { return }
        clear()
    }
    func clearResult() { guard !needsResultDecision else { return }; clear() }
    private func clear() { guidance.stop(); latestResult = nil; engine = nil; resultSaved = false }
    private func changed() { handleChanges(); persist() }
    private func persist() { if let record = engine?.record, isActive { store?.checkpoint(record) } }
    private func handleChanges() {
        guard let engine else { return }
        let cue = GuidanceCue.preferred(in: engine.record.events.dropFirst(processedEvents).compactMap(\.guidance))
        processedEvents = engine.record.events.count
        if let cue {
            lastGuidanceText = cue.speech
            guidance.speak(cue, voice: engine.record.settings.voice, haptics: engine.record.settings.haptics)
        }
        if self.engine?.phase.isFinished == true && latestResult == nil {
            timer?.invalidate(); timer = nil; motion.stop()
            UIApplication.shared.isIdleTimerDisabled = false
            latestResult = self.engine?.record
            if let latestResult { store?.checkpoint(latestResult) }
        }
    }
}
