import Combine
import Foundation
import OrientationCore
import XCTest
@testable import OrientationHapticsLab

@MainActor
final class ClockDirectionIntegrationTests: XCTestCase {
    func testResetConsumesFrontUntilUserLeavesAndReturns() async throws {
        let context = try Context()
        defer { context.cleanDefaults() }
        context.model.start()
        context.model.reset()
        XCTAssertEqual(context.haptic.resets, 1)
        context.model.simulate(heading: 1)
        context.model.simulate(heading: -1)
        XCTAssertEqual(context.haptic.angles, [])
        context.model.simulate(heading: 10)
        context.model.simulate(heading: 0)
        XCTAssertEqual(context.haptic.angles, [0])
        context.model.simulate(heading: 90)
        context.model.simulate(heading: 180)
        XCTAssertEqual(context.haptic.angles, [0, 90, 180])
        context.model.simulate(heading: -179)
        XCTAssertEqual(context.haptic.angles, [0, 90, 180])
        await context.finish()
    }

    func testDisplayAndSpeechChangesPreserveReferenceAndLogTheirChoices() async throws {
        let context = try Context()
        defer { context.cleanDefaults() }
        context.model.start()
        context.model.reset()
        context.model.simulate(heading: -30)
        let cycle = context.model.cycleNumber
        context.settings.setDisplayMode(.clock)
        context.settings.setSpeechStyle(.clock)
        context.settings.setSignalMode(.speech)
        context.model.applySettings()
        XCTAssertEqual(context.model.displayMode, .clock)
        XCTAssertEqual(context.model.relativeDegrees, -30)
        XCTAssertEqual(context.model.cycleNumber, cycle)
        XCTAssertTrue(context.model.isCalibrated)
        XCTAssertEqual(context.model.signals.speechStyle, .clock)
        context.model.simulate(heading: -60)
        context.model.stop()
        await context.archive.flush()
        let events = try XCTUnwrap(context.archive.records.first).hapticEvents
        XCTAssertEqual(events.last?.triggerAngleDegrees, -60)
        XCTAssertTrue(events.last?.patternID.contains("10시 방향") == true)
        XCTAssertTrue(events.last?.patternID.contains("표시=시계 방향") == true)
        try? FileManager.default.removeItem(at: context.directory)
    }

    @MainActor private struct Context {
        let model: LabModel
        let settings: HapticSettingsStore
        let haptic: CapturingDirectionOutput
        let archive: SessionStore
        let directory: URL
        let defaults: UserDefaults
        let suite: String
        init() throws {
            suite = "ClockIntegration.\(UUID())"
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            settings = HapticSettingsStore(defaults: defaults)
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            archive = SessionStore(fileURL: directory.appendingPathComponent("sessions.json"))
            haptic = CapturingDirectionOutput()
            let service = SignalService(mode: .haptic, outputs: [
                .haptic: haptic, .speech: CapturingDirectionOutput(), .beep: CapturingDirectionOutput()
            ])
            model = LabModel(signals: service, sessionStore: archive, settings: settings,
                             pedometer: EmptyClockWalkingFeed(), simulation: true)
        }
        func cleanDefaults() { defaults.removePersistentDomain(forName: suite) }
        func finish() async {
            model.stop()
            await archive.flush()
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

@MainActor
private final class CapturingDirectionOutput: SignalOutput {
    var angles: [Double] = []
    var resets = 0
    let state = SignalPlaybackState(status: "test")
    var statePublisher: AnyPublisher<SignalPlaybackState, Never> { Just(state).eraseToAnyPublisher() }
    func prepare() {}
    func stop() {}
    func playAngle(_ signedDegrees: Double, configuration: HapticConfiguration?) -> Bool {
        angles.append(signedDegrees); return true
    }
    func playReset() -> Bool { resets += 1; return true }
}

@MainActor
private final class EmptyClockWalkingFeed: WalkingFeed {
    func start(cycleID: UUID, from startDate: Date,
               onSample: @escaping @MainActor (WalkingSample) -> Void,
               onStatus: @escaping @MainActor (String) -> Void) {}
    func stop() {}
    func queryFinal(cycleID: UUID, from startDate: Date, to endDate: Date,
                    completion: @escaping @MainActor (WalkingSample?, String?) -> Void) {
        completion(nil, nil)
    }
}
