import Combine
import OrientationCore
import XCTest
@testable import OrientationHapticsLab

@MainActor
final class HapticResponsivenessTests: XCTestCase {
    func testHardwarePreparationDoesNotBlockAndStopKeepsEngineWarm() async throws {
        let driver = ControlledHapticDriver()
        let service = HapticService(driver: driver, supportsHaptics: true, isForeground: true)
        service.prepare()
        XCTAssertTrue(service.playReset(), "Request must return before the driver sends readiness.")
        await waitUntil { await driver.latestRevision >= 2 }
        XCTAssertNil(service.currentlyPlaying)
        let token = await driver.latestRevision
        await driver.emit(.playing, revision: token)
        await waitUntil { service.currentlyPlaying != nil }
        service.stop()
        await waitUntil { await driver.lastSuspend != nil }
        let suspended = await driver.suspension()
        XCTAssertEqual(suspended, false)
        XCTAssertNil(service.currentlyPlaying)
    }

    func testCancelledCallbacksCannotRestoreOldOverlay() async {
        let driver = ControlledHapticDriver()
        let service = HapticService(driver: driver, supportsHaptics: true, isForeground: true)
        service.playAngle(-30)
        await waitUntil { await driver.latestRevision > 0 }
        let old = await driver.latestRevision
        service.playAngle(90)
        await waitUntil { await driver.latestRevision > old }
        let current = await driver.latestRevision
        await driver.emit(.playing, revision: current)
        await waitUntil { service.currentlyPlayingAngle == 90 }
        await driver.emit(.finished, revision: old)
        await Task.yield()
        XCTAssertEqual(service.currentlyPlayingAngle, 90)
        service.stop()
        await driver.emit(.playing, revision: current)
        await Task.yield()
        XCTAssertNil(service.currentlyPlayingAngle)
    }

    func testMissingHardwareReplyTimesOutWithoutFreezingUI() async {
        let driver = ControlledHapticDriver()
        let service = HapticService(driver: driver, supportsHaptics: true, isForeground: true,
                                    responseTimeout: .milliseconds(30))
        service.playReset()
        await waitUntil { service.lastError != nil }
        XCTAssertNil(service.currentlyPlaying)
        await waitUntil { await driver.lastSuspend == true }
        let suspended = await driver.suspension()
        XCTAssertEqual(suspended, true)
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for asynchronous driver state")
    }
}

private actor ControlledHapticDriver: HapticDriving {
    var latestRevision: UInt = 0
    var lastSuspend: Bool?
    private var replies: [UInt: HapticReply] = [:]
    func prepare(revision: UInt, reply: @escaping HapticReply) {
        latestRevision = max(latestRevision, revision)
        replies[revision] = reply
    }
    func play(_ pulses: [HapticPulse], revision: UInt, reply: @escaping HapticReply) {
        latestRevision = max(latestRevision, revision)
        replies[revision] = reply
    }
    func cancel(revision: UInt, suspend: Bool) { lastSuspend = suspend }
    func emit(_ event: HapticDriverEvent, revision: UInt) { replies[revision]?(revision, event) }
    func suspension() -> Bool? { lastSuspend }
}

@MainActor
final class WalkingLifecycleTests: XCTestCase {
    func testDelayedHeadingDoesNotTerminateWalking() async throws {
        let context = try makeContext()
        context.model.start()
        context.heading.emit(heading: 0)
        context.model.reset()
        let stops = context.walking.stopCount
        context.heading.emit(heading: 0, age: 2)
        context.walking.emit(steps: 7)
        XCTAssertEqual(context.model.walk.steps, 7)
        XCTAssertEqual(context.walking.stopCount, stops)
        XCTAssertTrue(context.model.isCalibrated)
        await context.finish()
    }

    func testInvalidPostureOnlyInvalidatesDirectionAndStepsContinue() async throws {
        let context = try makeContext()
        context.model.start()
        context.heading.emit(heading: 0)
        context.model.reset()
        let stops = context.walking.stopCount
        context.heading.emit(heading: nil)
        XCTAssertFalse(context.model.isCalibrated)
        context.walking.emit(steps: 7)
        XCTAssertEqual(context.model.walk.steps, 7)
        XCTAssertEqual(context.walking.stopCount, stops)
        XCTAssertTrue(context.model.sessionStore.records.isEmpty)
        await context.finish()
    }

    func testPermissionAlertInactivePhaseKeepsWalkingCycle() async throws {
        let context = try makeContext()
        context.model.start()
        context.heading.emit(heading: 0)
        context.model.reset()
        let stops = context.walking.stopCount
        context.model.setAppActive(false)
        context.walking.emit(steps: 7)
        context.model.setAppActive(true)
        XCTAssertEqual(context.model.walk.steps, 7)
        XCTAssertTrue(context.model.isCalibrated)
        XCTAssertEqual(context.walking.stopCount, stops)
        await context.finish()
    }

    func testRepeatedResetArchivesSevenStepsAndStartsFreshCycle() async throws {
        let context = try makeContext()
        context.model.start()
        context.heading.emit(heading: 0)
        context.model.reset()
        context.walking.emit(steps: 7)
        context.heading.emit(heading: 0)
        context.model.reset()
        XCTAssertEqual(context.model.walk.steps, 0)
        XCTAssertEqual(context.model.sessionStore.records.first?.walk.steps, 7)
        context.walking.emit(steps: 2)
        XCTAssertEqual(context.model.walk.steps, 2)
        await context.finish()
    }

    @MainActor private struct Context {
        let model: LabModel
        let heading: ControlledHeadingFeed
        let walking: ControlledWalkingFeed
        let directory: URL
        func finish() async {
            model.stop()
            await model.sessionStore.flush()
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeContext() throws -> Context {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SessionStore(fileURL: directory.appendingPathComponent("sessions.json"))
        let heading = ControlledHeadingFeed()
        let walking = ControlledWalkingFeed()
        let outputs: [SignalMode: any SignalOutput] = Dictionary(uniqueKeysWithValues:
            SignalMode.allCases.map { ($0, SilentSignalOutput()) })
        let model = LabModel(signals: SignalService(mode: .haptic, outputs: outputs), sessionStore: store,
                             pedometer: walking, feed: heading, simulation: false)
        return Context(model: model, heading: heading, walking: walking, directory: directory)
    }
}

@MainActor
private final class ControlledHeadingFeed: HeadingFeed {
    var callback: (@MainActor (HeadingSample) -> Void)?
    func start(onSample: @escaping @MainActor (HeadingSample) -> Void,
               onError: @escaping @MainActor (String) -> Void) { callback = onSample }
    func stop() { callback = nil }
    func emit(heading: Double?, age: Double = 0) {
        callback?(HeadingSample(heading: heading, timestamp: ProcessInfo.processInfo.systemUptime - age,
                                receivedAt: Date()))
    }
}

@MainActor
private final class ControlledWalkingFeed: WalkingFeed {
    private var startDate = Date()
    private var callback: (@MainActor (WalkingSample) -> Void)?
    var stopCount = 0
    func start(cycleID: UUID, from startDate: Date,
               onSample: @escaping @MainActor (WalkingSample) -> Void,
               onStatus: @escaping @MainActor (String) -> Void) {
        self.startDate = startDate
        callback = onSample
    }
    func stop() { stopCount += 1; callback = nil }
    func queryFinal(cycleID: UUID, from startDate: Date, to endDate: Date,
                    completion: @escaping @MainActor (WalkingSample?, String?) -> Void) { completion(nil, nil) }
    func emit(steps: Int) {
        callback?(WalkingSample(startDate: startDate, endDate: startDate.addingTimeInterval(Double(steps)),
                                 steps: steps, distance: nil))
    }
}

@MainActor
private final class SilentSignalOutput: SignalOutput {
    let state = SignalPlaybackState(status: "test")
    var statePublisher: AnyPublisher<SignalPlaybackState, Never> { Just(state).eraseToAnyPublisher() }
    func prepare() {}
    func playAngle(_ signedDegrees: Double, configuration: HapticConfiguration?) -> Bool { true }
    func playReset() -> Bool { true }
    func stop() {}
}
