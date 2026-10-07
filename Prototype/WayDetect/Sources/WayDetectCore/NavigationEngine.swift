import Foundation

/// Pure state machine. Sensor acquisition is never started/stopped by a route transition.
public struct NavigationEngine {
    public private(set) var record: SessionRecord
    public private(set) var phase: RunPhase = .reference
    public private(set) var spotIndex = 0
    public private(set) var legSteps = 0
    public private(set) var stepGoal: Int
    public private(set) var reference: Double?
    public private(set) var target: Double?
    public private(set) var latest: MotionObservation?
    public private(set) var now = 0.0
    public private(set) var pauseReason = ""
    public private(set) var needsReanchor = false
    public private(set) var revision = 0
    public private(set) var isResettingDirection = false
    public private(set) var autoStartPending = false
    private var stability = StabilityWindow()
    private var stillness = StillnessWindow()
    private var holdAfter = 0.0
    private var hasStartedLeg = false
    private var resetUsesRouteClock = true
    private var walkStarted = Double.infinity
    private var lastEstimatedStep = -Double.infinity
    private var recentEstimatedSteps: [Double] = []
    private var lastTrace = -Double.infinity
    private var lastCorrection = -Double.infinity
    private var correctionActive = false
    private var pausedForDirection = false
    private var deviationSince: Double?
    private var severeSince: Double?
    private var invalidSince: Double?
    private var alignedSince: Double?
    private var alignedAnnounced = false
    private var referenceTime = 0.0
    private var lastStepTime = 0.0
    private var noStepAnnounced = false
    private var resumeAllowed = false

    public init(route: Route, settings: TrackingSettings = .init(), isDemo: Bool = false, date: Date = Date()) {
        record = SessionRecord(startedAt: date, route: route, settings: settings, isDemo: isDemo)
        stepGoal = route.spots.first?.steps ?? 0
        if let error = route.validationMessage {
            phase = .ended; record.outcome = error; record.endedAt = date
        } else { emit("시작", "정면을 정하고 12시를 설정하세요.", cue: .init("정면 설정.", haptic: .start)) }
    }
    public var currentSpot: RouteSpot { record.route.spots.indices.contains(spotIndex) ? record.route.spots[spotIndex] : RouteSpot() }
    public var sensorFresh: Bool { latest.map { $0.isValid && now - $0.time <= 0.8 && now >= $0.time - 0.1 } ?? false }
    public var referenceReady: Bool { sensorFresh && stability.ready }
    public var referenceProgress: Double { sensorFresh ? stability.progress : 0 }
    public var arrivalProgress: Double { phase == .arrival && sensorFresh ? min(1, stillness.duration / 1.5) : 0 }
    public var resetProgress: Double { isResettingDirection && sensorFresh ? min(1, stillness.duration) : 0 }
    public var error: Double { guard let target, let latest else { return 0 }; return Angles.difference(target: target, current: latest.heading) }
    public var directionText: String { target != nil && sensorFresh ? Angles.instruction(error: error) : "방향 확인 중" }
    public var aligned: Bool { sensorFresh && target != nil && abs(error) <= 12 && alignedSince.map { (latest?.time ?? 0) - $0 + 1e-9 >= 0.6 } == true }
    public var canStartWalking: Bool { phase == .aiming && aligned }
    public var canResume: Bool { phase == .paused && resumeAllowed && !needsReanchor && aligned }
    public var sensorStatus: String {
        guard let latest else { return "방향 센서 대기" }
        if now - latest.time > 0.8 { return "방향 수신 끊김" }
        if latest.gravityResidual > 0.15 { return "센서 좌표계 확인 필요" }
        if !latest.isValid { return "휴대폰을 세로로, 화면은 바깥쪽으로" }
        return "방향 수신 중"
    }

    public mutating func receive(_ sample: MotionObservation, at time: Double) {
        receiveBatch(sample, estimatedSteps: [], at: time)
    }

    /// Apply a complete mailbox batch before checking arrival. A step in the SAME
    /// batch must be able to cancel the stationary hold before the route advances.
    public mutating func receiveBatch(_ sample: MotionObservation?, estimatedSteps: [Double], at time: Double, stillnessInterrupted: Bool = false) {
        guard !phase.isFinished, time.isFinite else { return }
        if stillnessInterrupted && (phase == .arrival || isResettingDirection) {
            now = max(now, time); resetHold()
        }
        if let sample { updateMotion(sample, at: time) }
        if !estimatedSteps.isEmpty { receiveEstimatedSteps(estimatedSteps, at: time) }
        tick(at: time)
    }
    private mutating func updateMotion(_ sample: MotionObservation, at time: Double) {
        guard !phase.isFinished, sample.time.isFinite, time.isFinite,
              sample.time >= 0, sample.time <= time + 0.1,
              latest.map({ sample.time > $0.time }) ?? true else { return }
        if let previous = latest, sample.time - previous.time > 0.2 { alignedSince = nil }
        now = max(now, time); latest = sample
        stability.append(sample)
        if phase == .arrival || isResettingDirection {
            // A stationary but off-course body must not become the next spot's new front.
            if phase == .arrival && (!sensorFresh || target == nil || abs(error) > 12) { resetHold() }
            else if sample.time > holdAfter { stillness.append(sample) }
        }
        if sensorFresh && target != nil && abs(error) <= 12 {
            if alignedSince == nil { alignedSince = sample.time }
        } else { alignedSince = nil; alignedAnnounced = false }
        if sensorFresh { invalidSince = nil }
        else if invalidSince == nil { invalidSince = now }
    }

    public mutating func tick(at time: Double) {
        guard !phase.isFinished, time.isFinite else { return }
        now = max(now, time)
        if !sensorFresh {
            stillness.reset(); deviationSince = nil; severeSince = nil; alignedSince = nil
        }
        if [.aiming, .walking].contains(phase) {
            if let latest, now - latest.time > 1 {
                pause("방향 수신이 끊겼습니다. 멈춰서 휴대폰을 확인하세요.")
            } else if let invalidSince, now - invalidSince > 0.6 {
                pause("착용 방향을 확인하세요. 휴대폰은 배 앞에 세로로 고정합니다.")
            }
        }
        if [.aiming, .walking, .arrival].contains(phase), sensorFresh, now - referenceTime > 120 {
            needsReanchor = true
            pause("방향 재설정이 필요합니다.")
        }
        if isResettingDirection && sensorFresh && stillness.ready(for: 1) {
            finishDirectionReset()
        } else if phase == .arrival && sensorFresh && stillness.ready(for: 1.5) {
            completeArrival()
        }
        // Walking motion is expected here. Require a fresh, continuous heading
        // match, not another stationary hold after the user has already arrived.
        if phase == .aiming && autoStartPending && aligned {
            _ = startWalking(automatic: true)
        } else if phase == .aiming && !autoStartPending && aligned && !alignedAnnounced {
            alignedAnnounced = true
            emit("방향", "방향이 맞았습니다. 출발 버튼을 누르세요.", cue: .init("방향 맞음.", haptic: .success))
        }
        updateDirectionGuidance()
        if phase == .walking && sensorFresh && now - lastStepTime > 12 && !noStepAnnounced
            && deviationSince == nil && !correctionActive && now - lastCorrection >= 3 {
            noStepAnnounced = true
            emit("걸음 확인", "12초 동안 새 추정 걸음이 없습니다. 걷고 있다면 착용 상태를 확인하세요.",
                 cue: .init("걸음 확인.", haptic: .warning, priority: .status))
        }
        if now >= 1_800 { finish(outcome: "POC 측정 30분 종료") }
        trace()
    }

    private mutating func updateDirectionGuidance() {
        guard sensorFresh, target != nil, !needsReanchor,
              [.aiming, .walking, .arrival].contains(phase) || (phase == .paused && pausedForDirection) else { return }
        let magnitude = abs(error)
        // Enter at 18°, recover at 12°: waist sway at the boundary must not keep
        // restarting the first warning. This clock is independent of other speech.
        let threshold = phase == .aiming || phase == .arrival ? 12.0 : 18.0
        if magnitude > threshold { if deviationSince == nil { deviationSince = now } }
        else if magnitude <= 12 { deviationSince = nil }
        if magnitude > 75 { if severeSince == nil { severeSince = now } }
        else { severeSince = nil }
        if phase == .walking, let severeSince, now - severeSince >= 1.5 {
            pause("방향이 크게 벗어났습니다. 위치와 남은 걸음을 확인하세요.")
            pausedForDirection = true; correctionActive = true; lastCorrection = now
            return
        }
        if magnitude <= 12 {
            if correctionActive && aligned {
                correctionActive = false; lastCorrection = now
                emit("보정 완료", "기존 목표 방향으로 돌아왔습니다.", cue: .init("방향 맞음.", haptic: .success))
                // A later, separate deviation gets a fresh first-warning clock.
                deviationSince = nil
            }
            return
        }
        guard let deviationSince, now - deviationSince >= 1 else { return }
        // First walking/arrival warning is never delayed by the departure cue.
        // In aiming, allow the initial route announcement to finish first.
        let interval = correctionActive || phase == .aiming ? 3.0 : 0.0
        guard now - lastCorrection >= interval else { return }
        correctionActive = true; lastCorrection = now
        let text = phase == .arrival || phase == .paused ? "정지. " + directionText : directionText
        emit("보정", "현재 정면 기준 · " + directionText, cue: .init(text, haptic: .turn))
    }

    @discardableResult public mutating func setInitialReference() -> Bool {
        guard phase == .reference, referenceReady else { return false }
        setReference(); phase = .aiming; announceSpot(); return true
    }
    private mutating func setReference(heading: Double? = nil, useRouteClock: Bool = true, automatic: Bool = false) {
        reference = Angles.signed(heading ?? stability.mean); referenceTime = now; revision += 1
        target = Angles.signed((reference ?? 0) + (useRouteClock ? Angles.clockOffset(currentSpot.clock) : 0))
        needsReanchor = false; alignedSince = nil
        correctionActive = false; pausedForDirection = false; lastCorrection = -.infinity
        // Already-forward destinations need no extra "aligned" cue 0.6 s later:
        // it would interrupt the arrival/step instruction or reset confirmation.
        alignedAnnounced = !useRouteClock || currentSpot.clock == 12
        deviationSince = nil; severeSince = nil
        emit("12시 설정", automatic ? "목표 걸음 후 1.5초 정지한 정면을 새 12시로 설정했습니다." : "사용자가 선택한 현재 정면을 새 12시로 설정했습니다.")
    }
    private mutating func announceSpot(arrived: Bool = false) {
        lastCorrection = now
        emit("다음 스팟", "\(spotIndex + 1). \(currentSpot.name) · \(currentSpot.instruction)",
             cue: .init("\(arrived ? "도착. " : "")\(currentSpot.clock)시. \(stepGoal)걸음.", haptic: .turn))
    }
    @discardableResult public mutating func beginWalking() -> Bool {
        startWalking(automatic: false)
    }
    @discardableResult private mutating func startWalking(automatic: Bool) -> Bool {
        guard canStartWalking else { return false }
        autoStartPending = false
        phase = .walking; hasStartedLeg = true
        // On automatic departure the last 0.6 s of heading alignment have now
        // been confirmed. Preserve gait that already began within that window.
        walkStarted = automatic ? (alignedSince ?? now) : now
        lastStepTime = now; noStepAnnounced = false
        if automatic { legSteps = min(stepGoal, legSteps + recentEstimatedSteps.filter { $0 >= walkStarted }.count) }
        deviationSince = nil; severeSince = nil; correctionActive = false; pausedForDirection = false; lastCorrection = -.infinity
        let steps = max(0, stepGoal - legSteps)
        // For a straight next leg, the arrival cue already contains its direction
        // and steps. Do not interrupt that utterance 0.6 seconds later.
        let cue: GuidanceCue? = automatic && currentSpot.clock == 12 ? nil
            : .init("\(automatic ? "직진. " : "")\(steps)걸음.", haptic: .start)
        emit(automatic ? "자동 출발" : "출발", "남은 \(steps)걸음 이동 시작 · 실시간 추정 기준", cue: cue)
        if legSteps >= stepGoal { awaitArrival() }
        return true
    }

    /// Timestamps prevent delayed confirmation of steps before departure from leaking into this leg.
    public mutating func receiveEstimatedSteps(_ times: [Double], at time: Double) {
        guard !phase.isFinished, time.isFinite else { return }
        now = max(now, time)
        for stepTime in times.sorted() where stepTime.isFinite && stepTime >= 0 && stepTime <= now && stepTime > lastEstimatedStep {
            lastEstimatedStep = stepTime; record.estimatedTotal += 1
            recentEstimatedSteps.append(stepTime)
            recentEstimatedSteps.removeAll { $0 < now - 2 }
            if recentEstimatedSteps.count > 32 { recentEstimatedSteps.removeFirst(recentEstimatedSteps.count - 32) }
            if phase == .arrival || isResettingDirection { resetHold() }
            if phase == .walking, sensorFresh, stepTime >= walkStarted {
                legSteps += 1; lastStepTime = now; noStepAnnounced = false
                if legSteps >= stepGoal { awaitArrival() }
            }
        }
        trace(force: true)
    }
    public mutating func receiveSystemSteps(_ total: Int, at time: Double, source: String) {
        guard !phase.isFinished, total >= 0, time.isFinite else { return }
        now = max(now, time)
        record.systemTotal = max(record.systemTotal, total)
        emit("iOS 걸음", "\(source) · 원본 \(total)걸음 · 누적값, 추정 걸음에 더하지 않음")
    }
    public mutating func diagnostic(_ message: String) { guard !phase.isFinished else { return }; emit("진단", message) }

    private mutating func awaitArrival() {
        guard phase == .walking else { return }
        phase = .arrival; walkStarted = .infinity; resumeAllowed = false
        resetHold()
        let text = sensorFresh && abs(error) > 12 ? "정지. " + directionText : "멈추세요."
        if sensorFresh && abs(error) > 12 { correctionActive = true; lastCorrection = now }
        emit("도착 대기", "목표 추정 걸음 도달. 목표 방향으로 1.5초 연속 정지를 기다립니다.",
             cue: .init(text, haptic: .stop, priority: .safety))
    }
    /// Arrival is a user-chosen heuristic: target steps followed by 1.5 seconds of rest.
    /// It does not verify a geographic/physical position.
    private mutating func completeArrival() {
        guard phase == .arrival, sensorFresh, target != nil, abs(error) <= 12, stillness.ready(for: 1.5) else { return }
        let heading = stillness.mean
        record.confirmedSpots += 1
        emit("자동 도착", "\(currentSpot.name) · 목표 걸음 후 1.5초 정지로 도착 판정. 추정 \(legSteps)/\(stepGoal)걸음.")
        if spotIndex + 1 >= record.route.spots.count {
            finish(outcome: "경로 완료", completed: true)
        } else {
            spotIndex += 1; legSteps = 0; stepGoal = currentSpot.steps; hasStartedLeg = false
            setReference(heading: heading, automatic: true); phase = .aiming; autoStartPending = true; announceSpot(arrived: true)
        }
        resetHold()
    }
    private mutating func resetHold() { stillness.reset(); holdAfter = now }

    /// Explicit user override, available in every active phase. Counters never reset here.
    public mutating func requestDirectionReset() {
        guard !phase.isFinished, !isResettingDirection else { return }
        resetUsesRouteClock = !hasStartedLeg
        autoStartPending = false; correctionActive = false; pausedForDirection = false
        isResettingDirection = true; phase = .paused; resumeAllowed = false
        walkStarted = .infinity; target = nil; alignedSince = nil; alignedAnnounced = false
        resetHold()
        emit("방향 재설정 시작", "걸음 수를 유지하고 현재 정면을 다시 설정합니다.", cue: .init("정면 보고 멈추세요.", haptic: .stop, priority: .safety))
    }
    private mutating func finishDirectionReset() {
        let heading = stillness.mean
        setReference(heading: heading, useRouteClock: resetUsesRouteClock)
        isResettingDirection = false; pauseReason = ""; invalidSince = nil
        phase = hasStartedLeg && legSteps >= stepGoal ? .arrival : .aiming
        resetHold()
        emit("방향 재설정 완료", "걸음 \(legSteps)/\(stepGoal) 유지. 현재 정면으로 기준을 재설정했습니다.",
             cue: .init("재설정 완료.", haptic: .success))
    }
    public mutating func pause(_ reason: String = "위치와 남은 걸음을 확인한 뒤 계속하세요.") {
        guard !phase.isFinished, phase != .paused || isResettingDirection else { return }
        autoStartPending = false; pausedForDirection = false; correctionActive = false
        isResettingDirection = false; resetHold()
        resumeAllowed = phase == .walking || phase == .aiming || phase == .arrival
        phase = .paused; pauseReason = reason; walkStarted = .infinity
        let cue = target != nil && sensorFresh && !needsReanchor ? "정지. " + Angles.instruction(error: error) : "정지. 방향 확인."
        emit("정지", reason, cue: .init(cue, haptic: .warning, priority: .safety))
    }
    @discardableResult public mutating func resume(remainingSteps: Int) -> Bool {
        guard canResume, (1...300).contains(remainingSteps) else { return false }
        stepGoal = remainingSteps; legSteps = 0; revision += 1
        phase = .aiming
        emit("재개 확인", "사용자가 위치 확인 후 남은 걸음을 \(remainingSteps)걸음으로 설정. 기존 목표 방향 유지.")
        return beginWalking()
    }
    /// Use only after user confirms they returned to the last known spot, never silently at a drifted position.
    public mutating func restartFromConfirmedSpot() {
        guard !phase.isFinished else { return }
        phase = .reference; reference = nil; target = nil; legSteps = 0; stepGoal = currentSpot.steps
        autoStartPending = false; correctionActive = false; pausedForDirection = false
        isResettingDirection = false; hasStartedLeg = false; resetHold()
        walkStarted = .infinity; alignedSince = nil; alignedAnnounced = false
        emit("스팟 재시작", "이전 확인 스팟으로 돌아왔음을 사용자가 확인했습니다.", cue: .init("정면 설정.", haptic: .warning))
    }
    public mutating func sensorStreamRestarted() {
        pause("방향 재설정이 필요합니다.")
        isResettingDirection = false; resetHold()
        needsReanchor = true; resumeAllowed = false; reference = nil; target = nil
        latest = nil; stability.reset(); alignedSince = nil; invalidSince = nil
        emit("센서 재시작", "이전 센서 좌표계 폐기. 기존 방향으로 재개 금지.")
    }
    public mutating func repeatInstruction() {
        guard !phase.isFinished else { return }
        if isResettingDirection {
            emit("다시 안내", "정면 보고 멈추세요.", cue: .init("정면 보고 멈추세요.", haptic: .stop)); return
        }
        let text: String
        switch phase {
        case .reference: text = "정면 설정."
        case .arrival: text = sensorFresh && abs(error) > 12 ? "정지. " + directionText : "멈춰 계세요."
        case .paused: text = "정지. " + directionText
        case .aiming: text = directionText
        case .walking: text = directionText + " \(max(0, stepGoal - legSteps))걸음."
        default: return
        }
        emit("다시 안내", text, cue: .init(text, haptic: phase == .paused ? .stop : .turn))
    }
    public mutating func finish(outcome: String = "사용자 종료", completed: Bool = false) {
        guard !phase.isFinished else { return }
        autoStartPending = false
        isResettingDirection = false; resetHold()
        phase = completed ? .completed : .ended; record.outcome = outcome
        record.endedAt = record.startedAt.addingTimeInterval(now)
        emit("종료", outcome, cue: .init(completed ? "도착. 완료." : "종료.", haptic: completed ? .success : .stop, priority: .safety))
        trace(force: true)
    }
    private mutating func emit(_ kind: String, _ message: String, cue: GuidanceCue? = nil) {
        record.events.append(RunEvent(time: now, spot: spotIndex, kind: kind, message: message, guidance: cue))
    }
    private mutating func trace(force: Bool = false) {
        guard force || now - lastTrace >= 0.1, let latest else { return }
        lastTrace = now
        record.samples.append(TraceSample(time: now, spot: spotIndex, revision: revision, phase: phase,
            relativeHeading: Angles.signed(latest.heading - (reference ?? latest.heading)),
            targetHeading: target.map { Angles.signed($0 - (reference ?? $0)) } ?? 0, error: error, steps: legSteps, stepGoal: stepGoal,
            estimatedTotal: record.estimatedTotal, systemTotal: record.systemTotal,
            verticalAcceleration: latest.verticalAcceleration.isFinite ? latest.verticalAcceleration : 0,
            sensorAge: max(0, now - latest.time), sensorValid: sensorFresh,
            rotationRate: latest.rotationRate.isFinite ? latest.rotationRate : 0,
            accelerationMagnitude: latest.acceleration.isFinite ? latest.acceleration : 0,
            horizontalProjection: latest.horizontalProjection.isFinite ? latest.horizontalProjection : 0,
            gravityResidual: latest.gravityResidual.isFinite ? latest.gravityResidual : -1))
    }
}
