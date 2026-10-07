import XCTest
@testable import WayDetectCore

final class NavigationEngineTests: XCTestCase {
    private func feed(_ e: inout NavigationEngine, heading: Double, duration: Double = 1.3, rotationRate: Double = 0) {
        let start = e.now
        for i in 1...max(1, Int(duration / 0.05)) {
            let t = start + Double(i) * 0.05
            e.receive(MotionObservation(time: t, heading: heading, rotationRate: rotationRate), at: t)
        }
    }
    private func walking(clock: Int = 12, steps: Int = 12) -> NavigationEngine {
        var e = NavigationEngine(route: Route(spots: [.init(clock: clock, steps: steps)]))
        feed(&e, heading: 0); XCTAssertTrue(e.setInitialReference())
        feed(&e, heading: Angles.clockOffset(clock)); XCTAssertTrue(e.beginWalking())
        return e
    }
    private func step(_ e: inout NavigationEngine, count: Int = 1) {
        for _ in 0..<count {
            let t = e.now + 0.1
            e.receiveBatch(MotionObservation(time: t, heading: e.latest?.heading ?? 0), estimatedSteps: [t], at: t)
        }
    }
    private func waitingForNextLeg(clock: Int, steps: Int = 3) -> NavigationEngine {
        var e = NavigationEngine(route: Route(spots: [.init(clock: 12, steps: 1), .init(clock: clock, steps: steps)]))
        feed(&e, heading: 0); XCTAssertTrue(e.setInitialReference())
        feed(&e, heading: 0); XCTAssertTrue(e.beginWalking()); step(&e)
        feed(&e, heading: 0, duration: 1.6)
        XCTAssertEqual(e.spotIndex, 1); XCTAssertEqual(e.phase, .aiming)
        XCTAssertTrue(e.autoStartPending)
        return e
    }
    func testEveryClockDirection() {
        for clock in 1...12 {
            XCTAssertEqual(Angles.clock(Angles.clockOffset(clock)), clock)
            let e = walking(clock: clock)
            XCTAssertEqual(e.phase, .walking)
            XCTAssertTrue(e.record.events.contains { $0.guidance?.speech.contains("\(clock)시") == true && $0.guidance?.speech.contains("12걸음") == true })
        }
        XCTAssertEqual(Angles.clock(360), 12)
        XCTAssertEqual(Angles.clock(-90), 9)
        XCTAssertEqual(Angles.clock(180), 6)
        XCTAssertEqual(Angles.clock(-180), 6)
        XCTAssertEqual(Angles.clock(15), 1)
        XCTAssertEqual(Angles.clock(-15), 11)
        XCTAssertEqual(Angles.instruction(error: 0), "정면.")
        XCTAssertEqual(Angles.instruction(error: 30), "1시로.")
        XCTAssertEqual(Angles.instruction(error: 14), "조금 오른쪽.")
        XCTAssertEqual(Angles.instruction(error: -14), "조금 왼쪽.")
    }
    func testScreenNormalFromReferenceToDeviceMatrixForPortraitBellyMount() {
        for tilt in [60.0, 75, 90, 105, 120] {
            for yaw in [-179.0, -90, -30, 0, 30, 90, 179] {
                let pitch = tilt * .pi / 180, turn = yaw * .pi / 180
                // Construct the known physical screen normal in world space, independently of quaternions.
                // These are row 3 of the passive reference->device DCM.
                let h = Angles.heading(screenX: -sin(turn)*sin(pitch), screenY: -cos(turn)*sin(pitch), screenZ: cos(pitch))
                XCTAssertEqual(Angles.signed(h.degrees - 90), yaw, accuracy: 1e-8)
                XCTAssertGreaterThan(h.projection, 0.8)
            }
        }
        XCTAssertEqual(Angles.heading(screenX: 0, screenY: 0, screenZ: 1).projection, 0)
        XCTAssertFalse(Angles.heading(screenX: .nan, screenY: 0, screenZ: 1).degrees.isFinite)
    }
    func testReferenceNeedsRecentStableSensorAndExplicitAction() {
        var e = NavigationEngine(route: .example)
        XCTAssertFalse(e.setInitialReference())
        feed(&e, heading: 179)
        XCTAssertEqual(e.phase, .reference)
        XCTAssertTrue(e.referenceReady)
        e.tick(at: e.now + 1.2)
        XCTAssertFalse(e.setInitialReference())
        feed(&e, heading: -179)
        XCTAssertTrue(e.setInitialReference())
    }
    func testStableWindowCrossesWrapWithoutBeingUnstable() {
        var e = NavigationEngine(route: .example)
        for i in 1...30 {
            let t = Double(i) * 0.05
            e.receive(MotionObservation(time: t, heading: i % 2 == 0 ? 179 : -179), at: t)
        }
        XCTAssertTrue(e.referenceReady)
        XCTAssertTrue(e.setInitialReference())
        XCTAssertLessThan(abs(abs(e.reference!) - 180), 1)
    }
    func testTwoSpotsAutomaticallyRefreshFromStoppedFrontAfterQuota() {
        var e = NavigationEngine(route: Route(spots: [.init(clock: 3, steps: 2), .init(clock: 9, steps: 3)]))
        feed(&e, heading: 50); XCTAssertTrue(e.setInitialReference())
        XCTAssertEqual(e.target!, 140, accuracy: 0.001)
        feed(&e, heading: 140); XCTAssertTrue(e.beginWalking()); step(&e, count: 2)
        XCTAssertEqual(e.phase, .arrival); XCTAssertEqual(e.spotIndex, 0)
        XCTAssertEqual(e.record.confirmedSpots, 0)
        feed(&e, heading: 142, duration: 1.3)
        XCTAssertEqual(e.phase, .arrival)
        XCTAssertEqual(e.reference!, 50, accuracy: 0.001)
        feed(&e, heading: 142, duration: 0.4)
        XCTAssertEqual(e.phase, .aiming); XCTAssertEqual(e.spotIndex, 1)
        XCTAssertEqual(e.record.confirmedSpots, 1)
        XCTAssertEqual(e.reference!, 142, accuracy: 0.001)
        XCTAssertEqual(e.target!, 52, accuracy: 0.001)
        XCTAssertEqual(e.legSteps, 0)
        XCTAssertTrue(e.autoStartPending)
        // A later spot starts after its new target direction is held steadily.
        feed(&e, heading: 52, duration: 2)
        XCTAssertEqual(e.phase, .walking); XCTAssertEqual(e.record.confirmedSpots, 1)
        XCTAssertFalse(e.autoStartPending)
        step(&e, count: 3)
        XCTAssertEqual(e.phase, .arrival)
        feed(&e, heading: 52, duration: 1.8)
        XCTAssertEqual(e.phase, .completed); XCTAssertEqual(e.record.confirmedSpots, 2)
    }
    func testAlreadyForwardInstructionsAreNotInterruptedByAlignmentCue() {
        var e = NavigationEngine(route: Route(spots: [.init(clock: 12, steps: 1), .init(clock: 12, steps: 1)]))
        feed(&e, heading: 0); XCTAssertTrue(e.setInitialReference())
        let afterSetup = e.record.events.count
        feed(&e, heading: 0)
        XCTAssertFalse(e.record.events.dropFirst(afterSetup).contains { $0.kind == "방향" })
        XCTAssertTrue(e.beginWalking()); step(&e)
        feed(&e, heading: 0, duration: 1.7)
        let afterArrival = e.record.events.count
        feed(&e, heading: 0)
        XCTAssertEqual(e.spotIndex, 1)
        XCTAssertFalse(e.record.events.dropFirst(afterArrival).contains { $0.kind == "방향" })
        e.requestDirectionReset(); feed(&e, heading: 20)
        let afterReset = e.record.events.count
        feed(&e, heading: 20)
        XCTAssertFalse(e.record.events.dropFirst(afterReset).contains { $0.kind == "방향" })
    }
    func testDriftGivesClockCorrectionWithoutStoppingStepsOrChangingReference() {
        var e = walking(); let original = e.reference
        feed(&e, heading: -30, duration: 6)
        XCTAssertEqual(e.phase, .walking); XCTAssertEqual(e.reference, original)
        XCTAssertTrue(e.record.events.contains { $0.kind == "보정" && $0.guidance?.speech.contains("1시로") == true })
        step(&e); XCTAssertEqual(e.legSteps, 1)
        XCTAssertFalse(e.record.events.compactMap(\.guidance).contains { $0.speech.contains("도") })
    }
    func testFirstCorrectionFollowsOneSecondOfDriftDespiteDepartureAndReplaySpeech() {
        var e = walking()
        let departure = e.now
        feed(&e, heading: -30, duration: 0.6)
        XCTAssertFalse(e.record.events.contains { $0.kind == "보정" })
        e.repeatInstruction()
        feed(&e, heading: -30, duration: 0.3)
        XCTAssertFalse(e.record.events.contains { $0.kind == "보정" })
        feed(&e, heading: -30, duration: 0.3)
        let corrections = e.record.events.filter { $0.kind == "보정" }
        XCTAssertEqual(corrections.count, 1)
        XCTAssertEqual(corrections.first?.guidance?.speech, "1시로.")
        XCTAssertLessThan((corrections.first?.time ?? .infinity) - departure, 1.3)
    }
    func testCorrectionRepeatTimerIsIndependentOfOtherSpeech() {
        var e = walking()
        feed(&e, heading: -30, duration: 1.2)
        let first = e.record.events.last { $0.kind == "보정" }?.time
        XCTAssertNotNil(first)
        feed(&e, heading: -30, duration: 2)
        e.repeatInstruction()
        feed(&e, heading: -30, duration: 0.6)
        XCTAssertEqual(e.record.events.filter { $0.kind == "보정" }.count, 1)
        feed(&e, heading: -30, duration: 0.6)
        let corrections = e.record.events.filter { $0.kind == "보정" }
        XCTAssertEqual(corrections.count, 2)
        if corrections.count == 2 {
            XCTAssertGreaterThanOrEqual(corrections[1].time - corrections[0].time, 3 - 1e-6)
            XCTAssertLessThan(corrections[1].time - corrections[0].time, 3.15)
        }
    }
    func testCorrectionHysteresisSurvivesWobbleBetweenTwelveAndEighteenDegrees() {
        var e = walking()
        feed(&e, heading: -22, duration: 0.65)
        feed(&e, heading: -16, duration: 0.6)
        XCTAssertEqual(e.record.events.filter { $0.kind == "보정" }.count, 1)
        XCTAssertEqual(e.phase, .walking)
        feed(&e, heading: -17, duration: 0.7)
        XCTAssertFalse(e.record.events.contains { $0.kind == "보정 완료" })
    }
    func testCorrectionRecoveryAnnouncesOnlyAfterStableAlignmentAndAllowsNewDrift() {
        var e = walking()
        feed(&e, heading: -30, duration: 1.2)
        feed(&e, heading: 0, duration: 0.4)
        XCTAssertFalse(e.record.events.contains { $0.kind == "보정 완료" })
        feed(&e, heading: 0, duration: 0.4)
        let recovered = e.record.events.filter { $0.kind == "보정 완료" }
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered.first?.guidance?.speech, "방향 맞음.")
        feed(&e, heading: 0)
        XCTAssertEqual(e.record.events.filter { $0.kind == "보정 완료" }.count, 1)
        feed(&e, heading: 30, duration: 1.2)
        XCTAssertEqual(e.record.events.filter { $0.kind == "보정" }.count, 2)
        XCTAssertEqual(e.record.events.last { $0.kind == "보정" }?.guidance?.speech, "11시로.")
    }
    func testWalkingCorrectionRecoveryDoesNotRequireBodyStillness() {
        var e = walking()
        feed(&e, heading: -30, duration: 1.2)
        let start = e.now
        for index in 1...15 {
            let t = start + Double(index) * 0.05
            e.receive(.init(time: t, heading: 0, rotationRate: 25, acceleration: 0.12), at: t)
        }
        XCTAssertEqual(e.phase, .walking)
        let recovery = e.record.events.filter { $0.kind == "보정 완료" }
        XCTAssertEqual(recovery.count, 1)
        XCTAssertEqual(recovery.first?.guidance?.speech, "방향 맞음.")
    }
    func testNoStepWarningDoesNotReplaceDirectionCorrection() {
        var e = walking()
        feed(&e, heading: 0, duration: 11)
        let beforeDrift = e.record.events.count
        feed(&e, heading: -30, duration: 2)
        let events = Array(e.record.events.dropFirst(beforeDrift))
        XCTAssertTrue(events.contains { $0.kind == "보정" })
        XCTAssertFalse(events.contains { $0.kind == "걸음 확인" })
        XCTAssertEqual(events.last(where: { $0.guidance != nil })?.kind, "보정")
    }
    func testDirectionMatchingAlsoSpeaksCurrentClockWithoutStartingFirstLeg() {
        var e = NavigationEngine(route: Route(spots: [.init(clock: 3, steps: 12)]))
        feed(&e, heading: 0); XCTAssertTrue(e.setInitialReference())
        feed(&e, heading: 30, duration: 3.4)
        XCTAssertEqual(e.phase, .aiming)
        XCTAssertEqual(e.record.events.last { $0.kind == "보정" }?.guidance?.speech, "2시로.")
        feed(&e, heading: 90)
        XCTAssertEqual(e.phase, .aiming); XCTAssertTrue(e.canStartWalking)
        XCTAssertFalse(e.autoStartPending)
    }
    func testSevereDeviationKeepsGivingUpdatedDirectionsWhilePaused() {
        var e = walking()
        let reference = e.reference
        feed(&e, heading: 90, duration: 2)
        XCTAssertEqual(e.phase, .paused)
        let pausedEvents = e.record.events.count
        feed(&e, heading: 60, duration: 3.4)
        XCTAssertEqual(e.phase, .paused); XCTAssertEqual(e.reference, reference)
        XCTAssertTrue(e.record.events.dropFirst(pausedEvents).contains {
            $0.kind == "보정" && $0.guidance?.speech.contains("10시로.") == true
        })
        feed(&e, heading: 0)
        XCTAssertEqual(e.phase, .paused); XCTAssertTrue(e.canResume)
        XCTAssertTrue(e.record.events.contains { $0.kind == "보정 완료" })
    }
    func testGoalStepWhileFacingWrongDirectionCannotSilentlyArrive() {
        var e = walking(steps: 1)
        let reference = e.reference
        let t = e.now + 0.1
        e.receiveBatch(.init(time: t, heading: 30), estimatedSteps: [t], at: t)
        XCTAssertEqual(e.phase, .arrival)
        XCTAssertEqual(e.record.events.last { $0.kind == "도착 대기" }?.guidance?.speech, "정지. 11시로.")
        feed(&e, heading: 30, duration: 2)
        XCTAssertEqual(e.phase, .arrival); XCTAssertEqual(e.record.confirmedSpots, 0)
        XCTAssertEqual(e.reference, reference); XCTAssertEqual(e.arrivalProgress, 0)
        feed(&e, heading: 30, duration: 1.3)
        XCTAssertTrue(e.record.events.contains { $0.kind == "보정" && $0.guidance?.speech == "정지. 11시로." })
        feed(&e, heading: 0, duration: 1.3)
        XCTAssertEqual(e.phase, .arrival); XCTAssertEqual(e.record.confirmedSpots, 0)
        feed(&e, heading: 0, duration: 0.4)
        XCTAssertEqual(e.phase, .completed)
    }
    func testStraightNextLegAutomaticallyStartsWithoutInterruptingArrivalInstruction() {
        var e = waitingForNextLeg(clock: 12)
        let afterArrival = e.record.events.count
        feed(&e, heading: 0, duration: 0.4)
        XCTAssertEqual(e.phase, .aiming)
        feed(&e, heading: 0, duration: 0.4)
        XCTAssertEqual(e.phase, .walking); XCTAssertFalse(e.autoStartPending)
        XCTAssertFalse(e.record.events.dropFirst(afterArrival).contains { $0.guidance != nil })
        step(&e)
        XCTAssertEqual(e.legSteps, 1)
    }
    func testTurnedNextLegStartsAfterAlignmentWhileBodyIsMoving() {
        var e = waitingForNextLeg(clock: 3)
        feed(&e, heading: 0, duration: 2)
        XCTAssertEqual(e.phase, .aiming); XCTAssertTrue(e.autoStartPending)
        feed(&e, heading: 90, duration: 0.4, rotationRate: 30)
        XCTAssertEqual(e.phase, .aiming); XCTAssertTrue(e.autoStartPending)
        feed(&e, heading: 90, duration: 0.4, rotationRate: 30)
        XCTAssertEqual(e.phase, .walking); XCTAssertFalse(e.autoStartPending)
        XCTAssertEqual(e.record.events.last(where: { $0.guidance != nil })?.guidance?.speech, "직진. 3걸음.")
    }
    func testAutomaticStartRequiresNewSensorSamplesAndRestartsHoldAfterGap() {
        var e = waitingForNextLeg(clock: 3)
        feed(&e, heading: 90, duration: 0.4)
        e.tick(at: e.now + 0.35)
        XCTAssertEqual(e.phase, .aiming)
        let t = e.now + 0.05
        e.receive(.init(time: t, heading: 90), at: t)
        feed(&e, heading: 90, duration: 0.4)
        XCTAssertEqual(e.phase, .aiming)
        feed(&e, heading: 90, duration: 0.3)
        XCTAssertEqual(e.phase, .walking)
    }
    func testMovementBetweenUIPollsDoesNotBlockAlignedAutomaticStart() {
        var e = waitingForNextLeg(clock: 3)
        feed(&e, heading: 90, duration: 0.4)
        let t = e.now + 0.05
        e.receiveBatch(.init(time: t, heading: 90), estimatedSteps: [], at: t, stillnessInterrupted: true)
        feed(&e, heading: 90, duration: 0.15)
        XCTAssertEqual(e.phase, .aiming)
        feed(&e, heading: 90, duration: 0.2)
        XCTAssertEqual(e.phase, .walking)
    }
    func testInvalidPostureRestartsAutomaticAlignment() {
        var e = waitingForNextLeg(clock: 3)
        feed(&e, heading: 90, duration: 0.4)
        let t = e.now + 0.05
        e.receive(.init(time: t, heading: 90, horizontalProjection: 0.4), at: t)
        feed(&e, heading: 90, duration: 0.4)
        XCTAssertEqual(e.phase, .aiming)
        feed(&e, heading: 90, duration: 0.3)
        XCTAssertEqual(e.phase, .walking)
    }
    func testAlignedOngoingGaitStartsNextLegAndCountsConfirmedSteps() {
        var e = waitingForNextLeg(clock: 3)
        let alignmentStart = e.now
        for i in 1...16 {
            let t = alignmentStart + Double(i) * 0.05
            e.receiveBatch(.init(time: t, heading: 90, rotationRate: 30, acceleration: 0.15),
                           estimatedSteps: [], at: t, stillnessInterrupted: true)
        }
        XCTAssertEqual(e.phase, .walking)
        XCTAssertEqual(e.legSteps, 0)
        XCTAssertEqual(e.record.events.filter { $0.kind == "자동 출발" }.count, 1)

        // The detector still confirms two cycles together; this regression only
        // removes the extra stationary gate that discarded detected next-leg gait.
        var detector = StepDetector()
        let gaitStart = e.now
        for i in 1...90 {
            let t = gaitStart + Double(i) * 0.02
            let vertical = sin(Double(i) * 0.02 * 2 * .pi / 0.6) * 0.2
            let sample = MotionObservation(time: t, heading: 90, rotationRate: 30,
                                           acceleration: abs(vertical), verticalAcceleration: vertical)
            e.receiveBatch(sample, estimatedSteps: detector.receive(sample), at: t, stillnessInterrupted: true)
        }
        XCTAssertEqual(e.legSteps, 3)
        XCTAssertEqual(e.phase, .arrival)
    }
    func testAutomaticStartCountsSameBatchStepsInAlignmentWindowOnlyOnce() {
        var e = waitingForNextLeg(clock: 3)
        let start = e.now
        let totalBefore = e.record.estimatedTotal
        feed(&e, heading: 90, duration: 0.6, rotationRate: 30)
        XCTAssertEqual(e.phase, .aiming)
        let t = start + 0.7
        let pair = [start + 0.15, start + 0.55]
        e.receiveBatch(.init(time: t, heading: 90, rotationRate: 30, acceleration: 0.15),
                       estimatedSteps: pair, at: t, stillnessInterrupted: true)
        XCTAssertEqual(e.phase, .walking)
        XCTAssertEqual(e.legSteps, 2)
        XCTAssertEqual(e.record.estimatedTotal, totalBefore + 2)
        e.receiveBatch(.init(time: t + 0.1, heading: 90), estimatedSteps: pair, at: t + 0.1)
        XCTAssertEqual(e.legSteps, 2)
        XCTAssertEqual(e.record.estimatedTotal, totalBefore + 2)
    }
    func testAutomaticStartExcludesTurnStepsBeforeAlignedWindow() {
        var e = waitingForNextLeg(clock: 3)
        let t = e.now + 0.1
        e.receiveBatch(.init(time: t, heading: 45), estimatedSteps: [t], at: t)
        let totalBeforeAlignment = e.record.estimatedTotal
        feed(&e, heading: 90, duration: 0.8, rotationRate: 30)
        XCTAssertEqual(e.phase, .walking)
        XCTAssertEqual(e.legSteps, 0)
        XCTAssertEqual(e.record.estimatedTotal, totalBeforeAlignment)
    }
    func testAutomaticStartAcceptsDelayedPairFromConfirmedAlignmentWindow() {
        var e = waitingForNextLeg(clock: 3)
        let start = e.now
        feed(&e, heading: 90, duration: 0.8, rotationRate: 30)
        XCTAssertEqual(e.phase, .walking)
        let t = e.now + 0.1
        e.receiveBatch(.init(time: t, heading: 90),
                       estimatedSteps: [start + 0.2, start + 0.7], at: t)
        XCTAssertEqual(e.legSteps, 2)
    }
    func testAutomaticStartImmediatelyAwaitsArrivalWhenAlignmentStepsMeetQuota() {
        var e = waitingForNextLeg(clock: 3, steps: 1)
        let start = e.now
        let totalBefore = e.record.estimatedTotal
        feed(&e, heading: 90, duration: 0.6, rotationRate: 30)
        let t = start + 0.7
        e.receiveBatch(.init(time: t, heading: 90, rotationRate: 30),
                       estimatedSteps: [start + 0.15, start + 0.55], at: t)
        XCTAssertEqual(e.phase, .arrival)
        XCTAssertEqual(e.legSteps, 1)
        XCTAssertEqual(e.record.estimatedTotal, totalBefore + 2)
        XCTAssertFalse(e.autoStartPending)
        XCTAssertEqual(e.record.events.last(where: { $0.guidance != nil })?.guidance?.speech, "멈추세요.")
    }
    func testFirstLegStillRequiresExplicitStart() {
        var e = NavigationEngine(route: .example)
        feed(&e, heading: 0); XCTAssertTrue(e.setInitialReference())
        feed(&e, heading: 0, duration: 3)
        XCTAssertEqual(e.phase, .aiming); XCTAssertFalse(e.autoStartPending)
        XCTAssertTrue(e.canStartWalking); XCTAssertTrue(e.beginWalking())
    }
    func testPauseResetAndBackgroundCancelPendingAutomaticStart() {
        for interruption in ["pause", "reset", "background"] {
            var e = waitingForNextLeg(clock: 12)
            switch interruption {
            case "pause": e.pause()
            case "reset": e.requestDirectionReset()
            default: e.sensorStreamRestarted()
            }
            XCTAssertFalse(e.autoStartPending, interruption)
            feed(&e, heading: 0, duration: 2)
            XCTAssertFalse(e.autoStartPending, interruption)
            XCTAssertNotEqual(e.phase, .walking, interruption)
            XCTAssertEqual(e.legSteps, 0, interruption)
            if interruption == "reset" {
                XCTAssertEqual(e.phase, .aiming); XCTAssertTrue(e.canStartWalking)
                XCTAssertTrue(e.beginWalking())
            }
        }
    }
    func testCuePriorityKeepsCorrectionAheadOfLaterStatusAndSafetyAheadOfEverything() {
        let correction = GuidanceCue("1시로.", haptic: .turn, priority: .navigation)
        let stepStatus = GuidanceCue("걸음 확인.", haptic: .warning, priority: .status)
        let stop = GuidanceCue("정지.", haptic: .stop, priority: .safety)
        XCTAssertEqual(GuidanceCue.preferred(in: [correction, stepStatus])?.speech, "1시로.")
        XCTAssertEqual(GuidanceCue.preferred(in: [stop, correction, stepStatus])?.speech, "정지.")
        XCTAssertEqual(GuidanceCue.preferred(in: [correction, .init("11시로.", priority: .navigation)])?.speech, "11시로.")
        XCTAssertNil(GuidanceCue.preferred(in: []))
    }
    func testLegacyGuidanceWithoutPriorityStillDecodesAndCanBeSelected() throws {
        let data = Data(#"{"speech":"3시로.","haptic":"turn"}"#.utf8)
        let restored = try JSONDecoder().decode(GuidanceCue.self, from: data)
        XCTAssertEqual(restored.speech, "3시로.")
        XCTAssertEqual(restored.haptic, .turn)
        XCTAssertEqual(GuidanceCue.preferred(in: [restored, .init("걸음 확인.", priority: .status)])?.speech, "3시로.")
    }
    func testSevereDeviationPausesButDoesNotSetNewFront() {
        var e = walking(); let reference = e.reference
        feed(&e, heading: 90, duration: 2)
        XCTAssertEqual(e.phase, .paused); XCTAssertEqual(e.reference, reference)
        step(&e); XCTAssertEqual(e.legSteps, 0); XCTAssertEqual(e.record.estimatedTotal, 1)
    }
    func testStepsBeforeDepartureAndDuplicatesDoNotLeakIntoLeg() {
        var e = NavigationEngine(route: .example)
        feed(&e, heading: 0)
        let before = e.now
        XCTAssertTrue(e.setInitialReference()); feed(&e, heading: 0)
        XCTAssertTrue(e.beginWalking())
        let now = e.now + 0.1
        e.receiveEstimatedSteps([before, now], at: now)
        XCTAssertEqual(e.legSteps, 1); XCTAssertEqual(e.record.estimatedTotal, 2)
        e.receiveEstimatedSteps([before, now], at: now)
        XCTAssertEqual(e.legSteps, 1); XCTAssertEqual(e.record.estimatedTotal, 2)
    }
    func testStepsContinueGloballyInPauseAndArrival() {
        var e = walking(steps: 2)
        step(&e); e.pause(); step(&e)
        XCTAssertEqual(e.legSteps, 1); XCTAssertEqual(e.record.estimatedTotal, 2)
        feed(&e, heading: 0); XCTAssertTrue(e.resume(remainingSteps: 1))
        step(&e); XCTAssertEqual(e.phase, .arrival)
        step(&e, count: 2)
        XCTAssertEqual(e.legSteps, 1); XCTAssertEqual(e.record.estimatedTotal, 5)
    }
    func testSystemPedometerDoesNotDuplicateOrReplaceIMUSteps() {
        var e = walking()
        step(&e, count: 2)
        e.receiveSystemSteps(8, at: e.now, source: "live")
        e.receiveSystemSteps(8, at: e.now, source: "query")
        e.receiveSystemSteps(4, at: e.now, source: "old")
        XCTAssertEqual(e.record.systemTotal, 8)
        XCTAssertEqual(e.legSteps, 2); XCTAssertEqual(e.record.estimatedTotal, 2)
    }
    func testSensorLossFreezesLegAndReappearanceDoesNotAutoResume() {
        var e = walking()
        e.tick(at: e.now + 1.1); XCTAssertEqual(e.phase, .paused)
        step(&e); XCTAssertEqual(e.legSteps, 0)
        feed(&e, heading: 0); XCTAssertEqual(e.phase, .paused)
        XCTAssertTrue(e.resume(remainingSteps: 8)); XCTAssertEqual(e.stepGoal, 8)
    }
    func testBackgroundRestartInvalidatesCoordinatesAndPreservesProgressForReset() {
        var e = walking(steps: 12); step(&e, count: 3)
        e.requestDirectionReset(); XCTAssertTrue(e.isResettingDirection)
        e.sensorStreamRestarted()
        XCTAssertFalse(e.isResettingDirection)
        XCTAssertNil(e.reference); XCTAssertNil(e.target)
        XCTAssertEqual(e.legSteps, 3); XCTAssertEqual(e.stepGoal, 12)
        feed(&e, heading: 60)
        XCTAssertFalse(e.canResume); XCTAssertFalse(e.resume(remainingSteps: 5))
        XCTAssertEqual(e.phase, .paused)
        e.requestDirectionReset(); feed(&e, heading: 60)
        XCTAssertFalse(e.isResettingDirection); XCTAssertFalse(e.needsReanchor)
        XCTAssertEqual(e.phase, .aiming)
        XCTAssertEqual(e.target!, 60, accuracy: 0.001)
        XCTAssertEqual(e.legSteps, 3); XCTAssertEqual(e.stepGoal, 12)
    }
    func testStationaryBeforeStepQuotaNeverCountsAsArrival() {
        var e = walking(steps: 20); step(&e, count: 2)
        feed(&e, heading: 0, duration: 3)
        XCTAssertEqual(e.phase, .walking)
        XCTAssertEqual(e.legSteps, 2); XCTAssertEqual(e.record.confirmedSpots, 0)
    }
    func testArrivalNeverReusesStableSamplesFromBeforeStepQuota() {
        var e = walking(steps: 1)
        feed(&e, heading: 0, duration: 2)
        step(&e)
        XCTAssertEqual(e.phase, .arrival)
        feed(&e, heading: 0, duration: 1.3)
        XCTAssertEqual(e.phase, .arrival); XCTAssertEqual(e.record.confirmedSpots, 0)
        feed(&e, heading: 0, duration: 0.4)
        XCTAssertEqual(e.phase, .completed); XCTAssertEqual(e.record.confirmedSpots, 1)
    }
    func testArrivalDwellRestartsAfterMovementRotationOrInvalidSample() {
        for disturbance in ["movement", "rotation", "invalid"] {
            var e = walking(steps: 1); step(&e)
            feed(&e, heading: 0, duration: 1.4)
            let t = e.now + 0.05
            let sample = MotionObservation(time: t, heading: 0,
                rotationRate: disturbance == "rotation" ? 60 : 0,
                acceleration: disturbance == "movement" ? 0.3 : 0,
                horizontalProjection: disturbance == "invalid" ? 0.2 : 1)
            e.receive(sample, at: t)
            feed(&e, heading: 0, duration: 1.3)
            XCTAssertEqual(e.phase, .arrival, disturbance)
            XCTAssertEqual(e.record.confirmedSpots, 0, disturbance)
            feed(&e, heading: 0, duration: 0.4)
            XCTAssertEqual(e.phase, .completed, disturbance)
        }
    }
    func testArrivalDwellRequiresNewSamplesAndRestartsAfterSensorGap() {
        var e = walking(steps: 1); step(&e)
        feed(&e, heading: 0, duration: 1.4)
        // A UI timer must not complete the dwell without a new sensor sample.
        e.tick(at: e.now + 0.2)
        XCTAssertEqual(e.phase, .arrival); XCTAssertEqual(e.record.confirmedSpots, 0)
        let t = e.now + 0.1 // Total sample gap is 0.3 seconds.
        e.receive(MotionObservation(time: t, heading: 0), at: t)
        feed(&e, heading: 0, duration: 1.3)
        XCTAssertEqual(e.phase, .arrival); XCTAssertEqual(e.record.confirmedSpots, 0)
        feed(&e, heading: 0, duration: 0.4)
        XCTAssertEqual(e.phase, .completed)
    }
    func testSameBatchStepPreventsAutomaticArrivalBeforeStepIsProcessed() {
        var e = walking(steps: 1); step(&e)
        feed(&e, heading: 0, duration: 1.4)
        let t = e.now + 0.2
        e.receiveBatch(MotionObservation(time: t, heading: 0), estimatedSteps: [t], at: t)
        XCTAssertEqual(e.phase, .arrival); XCTAssertEqual(e.record.confirmedSpots, 0)
        XCTAssertEqual(e.legSteps, 1); XCTAssertEqual(e.record.estimatedTotal, 2)
        feed(&e, heading: 0, duration: 1.3)
        XCTAssertEqual(e.phase, .arrival)
        feed(&e, heading: 0, duration: 0.4)
        XCTAssertEqual(e.phase, .completed)
    }
    func testMovementBetweenUIPollsRestartsArrivalDwell() {
        var e = walking(steps: 1); step(&e)
        feed(&e, heading: 0, duration: 1.4)
        let t = e.now + 0.15
        e.receiveBatch(.init(time: t, heading: 0), estimatedSteps: [], at: t, stillnessInterrupted: true)
        XCTAssertEqual(e.phase, .arrival)
        feed(&e, heading: 0, duration: 1.3)
        XCTAssertEqual(e.phase, .arrival)
        feed(&e, heading: 0, duration: 0.4)
        XCTAssertEqual(e.phase, .completed)
    }
    func testResetDuringWalkingPreservesProgressAndMakesCurrentFrontTheTarget() {
        var e = walking(clock: 3, steps: 12); step(&e, count: 3)
        let revision = e.revision
        e.requestDirectionReset()
        XCTAssertTrue(e.isResettingDirection)
        feed(&e, heading: 120, duration: 0.8)
        XCTAssertTrue(e.isResettingDirection)
        XCTAssertEqual(e.legSteps, 3); XCTAssertEqual(e.stepGoal, 12)
        feed(&e, heading: 120, duration: 0.5)
        XCTAssertFalse(e.isResettingDirection); XCTAssertEqual(e.phase, .aiming)
        XCTAssertEqual(e.reference!, 120, accuracy: 0.001)
        XCTAssertEqual(e.target!, 120, accuracy: 0.001)
        XCTAssertGreaterThan(e.revision, revision)
        XCTAssertEqual(e.legSteps, 3); XCTAssertEqual(e.stepGoal, 12)
        // The graph must use the actual reset target, not the original 3 o'clock offset.
        feed(&e, heading: 120)
        XCTAssertEqual(e.record.samples.last!.targetHeading, 0, accuracy: 0.001)
        XCTAssertEqual(e.phase, .aiming)
        XCTAssertTrue(e.beginWalking()); step(&e)
        XCTAssertEqual(e.legSteps, 4); XCTAssertEqual(e.stepGoal, 12)
    }
    func testResetBeforeDepartureKeepsTheSpotsClockInstruction() {
        var e = NavigationEngine(route: Route(spots: [.init(clock: 3, steps: 12)]))
        feed(&e, heading: 0); XCTAssertTrue(e.setInitialReference())
        e.requestDirectionReset(); feed(&e, heading: 50)
        XCTAssertFalse(e.isResettingDirection); XCTAssertEqual(e.phase, .aiming)
        XCTAssertEqual(e.reference!, 50, accuracy: 0.001)
        XCTAssertEqual(e.target!, 140, accuracy: 0.001)
        XCTAssertEqual(e.legSteps, 0); XCTAssertEqual(e.stepGoal, 12)
    }
    func testResetRequiresNewStableSamplesAndRestartsAfterSameBatchStep() {
        var e = walking(); feed(&e, heading: 0, duration: 2)
        e.requestDirectionReset()
        XCTAssertTrue(e.isResettingDirection)
        feed(&e, heading: 0, duration: 0.9)
        let t = e.now + 0.2
        e.receiveBatch(MotionObservation(time: t, heading: 0), estimatedSteps: [t], at: t)
        XCTAssertTrue(e.isResettingDirection)
        XCTAssertEqual(e.legSteps, 0); XCTAssertEqual(e.record.estimatedTotal, 1)
        feed(&e, heading: 0, duration: 0.8)
        XCTAssertTrue(e.isResettingDirection)
        feed(&e, heading: 0, duration: 0.5)
        XCTAssertFalse(e.isResettingDirection); XCTAssertEqual(e.phase, .aiming)
    }
    func testResetAtArrivalRequiresASeparateNewArrivalDwell() {
        var e = walking(steps: 2); step(&e, count: 2)
        feed(&e, heading: 0, duration: 1.3)
        e.requestDirectionReset(); feed(&e, heading: 30, duration: 1.3)
        XCTAssertFalse(e.isResettingDirection)
        XCTAssertEqual(e.phase, .arrival); XCTAssertEqual(e.record.confirmedSpots, 0)
        XCTAssertEqual(e.legSteps, 2); XCTAssertEqual(e.stepGoal, 2)
        feed(&e, heading: 30, duration: 1)
        XCTAssertEqual(e.phase, .arrival)
        feed(&e, heading: 30, duration: 0.6)
        XCTAssertEqual(e.phase, .completed)
    }
    func testArrivalCanBeCancelledAndContinueWithConfirmedRemaining() {
        var e = walking(steps: 2); step(&e, count: 2)
        e.pause("아직 도착하지 않음"); feed(&e, heading: 0)
        XCTAssertTrue(e.resume(remainingSteps: 5)); XCTAssertEqual(e.stepGoal, 5)
    }
    func testExpiredReferenceCannotResumeWithoutReanchor() {
        var e = walking(steps: 300)
        feed(&e, heading: 0, duration: 121)
        XCTAssertEqual(e.phase, .paused); XCTAssertTrue(e.needsReanchor)
        XCTAssertFalse(e.resume(remainingSteps: 20))
    }
    func testInvalidTiltAndNonfiniteInputCannotSetReference() {
        var e = NavigationEngine(route: .example)
        for i in 1...40 {
            let t = Double(i) * 0.05
            e.receive(MotionObservation(time: t, heading: .nan, horizontalProjection: 0), at: t)
        }
        XCTAssertFalse(e.referenceReady); XCTAssertFalse(e.setInitialReference())
        XCTAssertNoThrow(try JSONEncoder().encode(e.record))
    }
    func testInconsistentCoordinateFrameCannotGuideWalking() {
        var e = walking()
        let start = e.now
        for i in 1...30 {
            let t = start + Double(i) * 0.05
            e.receive(.init(time: t, heading: 0, gravityResidual: 0.5), at: t)
        }
        XCTAssertEqual(e.phase, .paused)
        XCTAssertFalse(e.referenceReady)
        XCTAssertEqual(e.sensorStatus, "센서 좌표계 확인 필요")
        XCTAssertFalse(e.resume(remainingSteps: 10))
    }
    func testFinishedResultIsImmutableToLateSensorCallbacks() {
        var e = walking(); step(&e); e.finish()
        let events = e.record.events.count, samples = e.record.samples.count
        e.receiveSystemSteps(99, at: e.now + 5, source: "late")
        e.receiveEstimatedSteps([e.now + 1], at: e.now + 1)
        e.diagnostic("late"); e.tick(at: e.now + 10)
        XCTAssertEqual(e.record.events.count, events); XCTAssertEqual(e.record.samples.count, samples)
        XCTAssertEqual(e.record.estimatedTotal, 1); XCTAssertEqual(e.record.systemTotal, 0)
        XCTAssertNotNil(e.record.endedAt)
    }
    func testRecordRoundtripPreservesSpotReferenceEventsAndSources() throws {
        var e = walking(); step(&e); e.finish()
        let restored = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(e.record))
        XCTAssertEqual(restored.schemaVersion, 2); XCTAssertEqual(restored.estimatedTotal, 1)
        XCTAssertTrue(restored.events.contains { $0.kind == "12시 설정" })
        XCTAssertTrue(restored.samples.allSatisfy { $0.sensorValid })
    }
    func testInvalidRouteCannotStartOrCrash() {
        let e = NavigationEngine(route: Route(spots: []))
        XCTAssertEqual(e.phase, .ended); XCTAssertFalse(e.referenceReady)
        XCTAssertNotNil(Route(spots: [.init(clock: 13)]).validationMessage)
    }
}
