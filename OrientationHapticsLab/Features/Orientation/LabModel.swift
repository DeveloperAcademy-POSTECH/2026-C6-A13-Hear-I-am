import Combine
import Foundation
import OrientationCore
import UIKit

@MainActor
final class LabModel: ObservableObject {
    let signals: SignalService
    let sessionStore: SessionStore
    let settings: HapticSettingsStore
    @Published private(set) var simulatedSignalAngle: Int?
    private var simulatedSignalTask: Task<Void, Never>?
    @Published private(set) var walk = WalkSnapshot()
    @Published private(set) var stepStatus = "기준을 리셋하면 걸음 집계를 시작합니다."
    private let pedometer: any WalkingFeed
    private var walkingEstimator: WalkingEstimator?
    private var lastWalkHeadingAt: Date?
    private var hapticEvents: [HapticEventRecord] = []
    @Published private(set) var displayMode: DirectionDisplayMode = .angle
    @Published private(set) var relativeDegrees: Double = 0
    @Published private(set) var continuousDegrees: Double = 0
    @Published private(set) var isCalibrated = false
    @Published private(set) var isRunning = false
    @Published private(set) var canReset = false
    @Published private(set) var status = "아이폰을 허리에 세로로 고정해 주세요."
    @Published private(set) var cycleNumber = 0
    @Published private(set) var lastSignal = "아직 신호 없음"
    @Published private(set) var enabledAngles = Set(AngleCue.defaults.map(\.id))
    private let feed: any HeadingFeed
    private var tracker = RelativeHeadingTracker()
    private var detector = AngleLandmarkDetector()
    private var latestSample: HeadingSample?
    private var watchdog: Task<Void, Never>?
    private var editing = false

    let isSimulation: Bool
    private var appActive = true

    init(signals: SignalService = SignalService(), sessionStore: SessionStore = SessionStore(),
         settings: HapticSettingsStore = HapticSettingsStore(), pedometer: any WalkingFeed = PedometerFeed(),
         feed: any HeadingFeed = MotionFeed(), simulation: Bool? = nil) {
        self.signals = signals
        self.sessionStore = sessionStore
        self.settings = settings
        self.pedometer = pedometer
        self.feed = feed
        #if targetEnvironment(simulator)
        isSimulation = simulation ?? true
        #else
        isSimulation = simulation ?? false
        #endif
    }

    /// Permission alerts temporarily deactivate the scene; they must not end a walking cycle.
    func setAppActive(_ active: Bool) {
        appActive = active
        if !active { clearSimulatedSignal(); signals.stop() }
    }

    var directionLabel: String {
        abs(relativeDegrees) < 0.5 ? "정면" : relativeDegrees < 0 ? "왼쪽" : "오른쪽"
    }

    func start() {
        guard !isRunning else { return }
        applySettings()
        isRunning = true
        UIApplication.shared.isIdleTimerDisabled = true
        signals.prepare()
        if isSimulation {
            simulate(heading: 0)
            status = "시뮬레이터 · 가상 방향으로 신호 체험"
            return
        }
        status = "방향 센서 준비 중"
        feed.start(onSample: { [weak self] sample in self?.consume(sample) },
                   onError: { [weak self] error in self?.sensorFailed(error) })
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { return }
                if self.appActive, self.isCalibrated, let sample = self.latestSample,
                   ProcessInfo.processInfo.systemUptime - sample.timestamp > 1 {
                    self.invalidateReference(message: "방향 수신이 끊겼어요. 다시 기준을 설정해 주세요.")
                    self.latestSample = nil
                }
            }
        }
    }

    func stop(reason: SessionEndReason = .stopped) {
        clearSimulatedSignal()
        archiveCycle(reason: reason)
        feed.stop()
        watchdog?.cancel()
        watchdog = nil
        signals.stop()
        isRunning = false
        latestSample = nil
        invalidateReference(message: "측정 중지 · 시작 후 기준을 다시 설정해 주세요.")
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func reset() {
        guard isRunning, let sample = latestSample, let heading = sample.heading,
              isSimulation || (0..<0.5).contains(ProcessInfo.processInfo.systemUptime - sample.timestamp),
              tracker.reset(absoluteHeadingDegrees: heading) != nil else {
            status = "안정적인 방향을 받은 후 다시 눌러 주세요."
            UIAccessibility.post(notification: .announcement, argument: status)
            return
        }
        clearSimulatedSignal()
        let resetDate = Date()
        archiveCycle(reason: .reset, at: resetDate)
        detector.reset()
        _ = detector.update(relativeDegrees: 0)
        relativeDegrees = 0
        continuousDegrees = 0
        cycleNumber += 1
        isCalibrated = true
        status = settings.displayMode == .clock ? "현재 방향을 12시로 설정했어요." : "현재 방향을 0°로 설정했어요."
        // Speech output already announces reset; do not speak the same confirmation twice.
        if settings.signalMode != .speech { UIAccessibility.post(notification: .announcement, argument: status) }
        lastSignal = "기준 방향 리셋"
        startWalkingCycle(at: resetDate)
        if signals.playReset() { recordSignal(trigger: 0, patternID: "reset: \(signals.mode.title)") }
    }

    func applySettings() {
        displayMode = settings.displayMode
        if signals.mode != settings.signalMode { clearSimulatedSignal() }
        signals.setMode(settings.signalMode)
        signals.setSpeechStyle(settings.speechStyle)
        enabledAngles = settings.enabledAngles
        detector.setCues(AngleCue.defaults.filter { enabledAngles.contains($0.id) })
        if isCalibrated { _ = detector.update(relativeDegrees: relativeDegrees) }
    }

    func setEditing(_ value: Bool) {
        editing = value
        clearSimulatedSignal()
        signals.stop()
        detector.reset()
        if !value, isCalibrated { _ = detector.update(relativeDegrees: relativeDegrees) }
    }

    func preview(_ cue: AngleCue) {
        playCue(cue, isPreview: true)
    }

    private func playCue(_ cue: AngleCue, isPreview: Bool = false) {
        signals.setMode(settings.signalMode)
        signals.setSpeechStyle(settings.speechStyle)
        let configuration = settings.configuration(for: cue.signedDegrees)
        if signals.playAngle(Double(cue.signedDegrees), configuration: configuration) {
            recordSignal(trigger: Double(cue.signedDegrees),
                         patternID: "\(isPreview ? "preview: " : "")표시=\(settings.displayMode.title) · 음성=\(settings.speechStyle.title) · \(signals.mode.title): \(signals.description(for: cue.signedDegrees, configuration: configuration))")
        } else if isSimulation, signals.mode == .haptic {
            clearSimulatedSignal()
            simulatedSignalAngle = cue.signedDegrees
            simulatedSignalTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1200))
                guard !Task.isCancelled else { return }
                self?.simulatedSignalAngle = nil
            }
        }
    }

    private func clearSimulatedSignal() {
        simulatedSignalTask?.cancel()
        simulatedSignalTask = nil
        simulatedSignalAngle = nil
    }

    func simulate(heading: Double) {
        guard isSimulation, isRunning else { return }
        consume(HeadingSample(heading: heading, timestamp: ProcessInfo.processInfo.systemUptime, receivedAt: Date()))
    }

    private func consume(_ sample: HeadingSample) {
        guard isRunning, appActive else { return }
        if !isSimulation {
            guard sample.timestamp.isFinite,
                  (0..<0.5).contains(ProcessInfo.processInfo.systemUptime - sample.timestamp) else {
                // Ignore one stale callback. A UI delay is not evidence of a stopped pedometer.
                return
            }
            if let previous = latestSample, sample.timestamp <= previous.timestamp { return }
        }
        if !isSimulation, let previous = latestSample, sample.timestamp - previous.timestamp > 1 {
            invalidateReference(message: "방향 측정이 중단됐어요. 기준을 다시 설정해 주세요.")
        }
        latestSample = sample
        guard let heading = sample.heading else {
            invalidateReference(message: "아이폰을 세로로 세워 주세요. 기준을 다시 설정해야 해요.")
            return
        }
        canReset = true
        guard let reading = tracker.update(absoluteHeadingDegrees: heading) else {
            status = "준비됨 · 현재 방향을 0°로 설정해 주세요."
            return
        }
        relativeDegrees = reading.relativeDegrees
        continuousDegrees = reading.continuousDegrees
        recordWalkingHeading(sample)
        if !editing, let cue = detector.update(relativeDegrees: relativeDegrees) {
            lastSignal = settings.displayMode.label(Double(cue.signedDegrees))
            playCue(cue)
        }
    }

    private func sensorFailed(_ message: String) {
        stop(reason: .appInterrupted)
        status = "센서 오류: \(message)"
        UIAccessibility.post(notification: .announcement, argument: status)
    }

    private func invalidateReference(message: String) {
        clearSimulatedSignal()
        // A lost heading only invalidates direction. Continue counting steps in this cycle.
        tracker.clear()
        detector.reset()
        signals.stop()
        isCalibrated = false
        canReset = false
        status = message
        UIAccessibility.post(notification: .announcement, argument: status)
    }

    private func startWalkingCycle(at date: Date) {
        let id = UUID()
        walkingEstimator = WalkingEstimator(cycleID: id, startedAt: date)
        lastWalkHeadingAt = date
        hapticEvents = []
        walk = WalkSnapshot()
        if isSimulation {
            stepStatus = "시뮬레이터 · 실제 걸음 센서 없음"
            return
        }
        pedometer.start(cycleID: id, from: date, onSample: { [weak self] sample in
            guard let self, self.walkingEstimator?.cycleID == id,
                  let snapshot = self.walkingEstimator?.ingest(sample: sample, cycleID: id) else { return }
            self.walk = snapshot
        }, onStatus: { [weak self] message in
            guard self?.walkingEstimator?.cycleID == id else { return }
            self?.stepStatus = message
        })
    }

    private func recordWalkingHeading(_ sample: HeadingSample) {
        guard isCalibrated, let id = walkingEstimator?.cycleID else { return }
        // Use the sensor timestamp's age to align headings with pedometer wall-clock intervals.
        let age = max(0, ProcessInfo.processInfo.systemUptime - sample.timestamp)
        let date = Date().addingTimeInterval(-age)
        guard lastWalkHeadingAt.map({ date.timeIntervalSince($0) >= 0.1 }) ?? true else { return }
        if walkingEstimator?.recordHeading(degrees: relativeDegrees, at: date, cycleID: id) == true {
            lastWalkHeadingAt = date
        }
    }

    private func recordSignal(trigger: Double, patternID: String) {
        guard isCalibrated, walkingEstimator != nil else { return }
        hapticEvents.append(HapticEventRecord(
            date: Date(), headingDegrees: relativeDegrees,
            triggerAngleDegrees: trigger, patternID: patternID
        ))
    }

    private func archiveCycle(reason: SessionEndReason, at endDate: Date = Date()) {
        guard let estimator = walkingEstimator else { return }
        pedometer.stop()
        // Clear the live identity before starting any asynchronous final query.
        walkingEstimator = nil
        lastWalkHeadingAt = nil
        let record = SessionRecord(
            id: estimator.cycleID, startedAt: estimator.startedAt, endedAt: endDate,
            endReason: reason, lastAngleDegrees: relativeDegrees,
            hapticEvents: hapticEvents, walk: estimator.snapshot
        )
        sessionStore.append(record, completionNote: isSimulation ? "시뮬레이터 · 걸음 센서 미사용" : "최종 걸음 조회 중")
        hapticEvents = []
        stepStatus = "사이클 종료 · 마지막 수신값은 로그에 보관됩니다."
        guard !isSimulation else { return }
        pedometer.queryFinal(cycleID: estimator.cycleID, from: estimator.startedAt, to: endDate) { [weak self] sample, errorMessage in
            guard let self else { return }
            var savedEstimator = estimator
            if let sample, let finalized = savedEstimator.ingest(sample: sample, cycleID: estimator.cycleID) {
                self.sessionStore.reconcile(id: estimator.cycleID, walk: finalized,
                                            completionNote: "종료 구간 최종 조회 반영 · 센서 처리 지연에 따른 오차 가능")
            } else {
                self.sessionStore.reconcile(id: estimator.cycleID, walk: nil,
                                            completionNote: errorMessage ?? "종료 시 수신값 유지 · 최종 조회가 없거나 기존 값보다 오래됨")
            }
        }
    }
}
