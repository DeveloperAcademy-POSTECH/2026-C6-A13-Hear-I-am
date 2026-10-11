import AVFoundation
import Combine
import OrientationCore
import XCTest
@testable import OrientationHapticsLab

@MainActor
final class SignalModeSettingsTests: XCTestCase {
    func testAllModesPersistWithoutChangingCustomHapticsOrEnabledAngles() throws {
        try withDefaults { defaults in
            let store = HapticSettingsStore(defaults: defaults)
            XCTAssertEqual(store.signalMode, .haptic)
            store.setConfiguration(.init(preset: .long, intensity: 0.4, sharpness: 0.2), for: -60)
            store.setEnabled(90, enabled: false)
            let angles = store.settings
            for mode in SignalMode.allCases {
                store.setSignalMode(mode)
                let restored = HapticSettingsStore(defaults: defaults)
                XCTAssertEqual(restored.signalMode, mode)
                XCTAssertEqual(restored.settings, angles)
            }
        }
    }

    func testOldSettingsMigrateToHapticsWithoutLosingEdits() throws {
        try withDefaults { defaults in
            let old = Data(#"{"schemaVersion":1,"angles":{"30":{"enabled":false,"configuration":{"preset":"long","intensity":0.3,"sharpness":0.2}}}}"#.utf8)
            defaults.set(old, forKey: "orientationHaptics.angleSettings")
            let store = HapticSettingsStore(defaults: defaults)
            XCTAssertEqual(store.signalMode, .haptic)
            XCTAssertFalse(store.isEnabled(30))
            XCTAssertEqual(store.configuration(for: 30).preset, .long)
            XCTAssertNil(store.errorMessage)
            store.setSignalMode(.speech)
            let restored = HapticSettingsStore(defaults: defaults)
            XCTAssertEqual(restored.signalMode, .speech)
            XCTAssertEqual(restored.settings, store.settings)
        }
    }

    func testUnknownModeRetainsValidAnglesAndCanBeReplaced() throws {
        try withDefaults { defaults in
            defaults.set(Data(#"{"schemaVersion":2,"signalMode":"unknown","angles":{"-90":{"enabled":false,"configuration":{"preset":"double","intensity":0.6,"sharpness":0.4}}}}"#.utf8), forKey: "orientationHaptics.angleSettings")
            let store = HapticSettingsStore(defaults: defaults)
            XCTAssertEqual(store.signalMode, .haptic)
            XCTAssertFalse(store.isEnabled(-90))
            XCTAssertEqual(store.configuration(for: -90).preset, .double)
            XCTAssertNotNil(store.errorMessage)
            store.setSignalMode(.beep)
            XCTAssertNil(HapticSettingsStore(defaults: defaults).errorMessage)
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "SignalModeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}

@MainActor
final class SignalRoutingTests: XCTestCase {
    func testAngleAndResetReachOnlySelectedOutput() {
        let outputs = makeOutputs()
        let service = SignalService(mode: .haptic, outputs: outputs)
        for mode in SignalMode.allCases {
            service.setMode(mode)
            XCTAssertTrue(service.playAngle(-60))
            XCTAssertEqual(service.state.angle, -60)
            XCTAssertTrue(service.playReset())
            XCTAssertNil(service.state.angle)
            XCTAssertEqual(outputs[mode]?.angles, [-60])
            XCTAssertEqual(outputs[mode]?.resetCount, 1)
        }
        for mode in SignalMode.allCases {
            XCTAssertEqual(outputs[mode]?.angles.count, 1)
            XCTAssertEqual(outputs[mode]?.resetCount, 1)
        }
    }

    func testSwitchStopsOldOutputAndIgnoresItsDelayedStatus() throws {
        let outputs = makeOutputs()
        let old = try XCTUnwrap(outputs[.speech])
        let service = SignalService(mode: .speech, outputs: outputs)
        service.playAngle(-90)
        service.setMode(.beep)
        XCTAssertEqual(old.stopCount, 1)
        XCTAssertNil(service.state.angle)
        service.playAngle(30)
        let current = service.state
        old.state = .init(label: "obsolete", angle: -90, status: "late completion")
        XCTAssertEqual(service.state, current)
        service.stop()
        XCTAssertNil(service.state.angle)
        XCTAssertEqual(outputs[.beep]?.stopCount, 1)
    }

    func testReapplyingModeDoesNotInterruptAndFailureIsVisible() throws {
        let outputs = makeOutputs()
        let selected = try XCTUnwrap(outputs[.beep])
        let service = SignalService(mode: .beep, outputs: outputs)
        service.playAngle(90)
        service.setMode(.beep)
        XCTAssertEqual(selected.stopCount, 0)
        XCTAssertEqual(service.state.angle, 90)
        selected.acceptsPlayback = false
        XCTAssertFalse(service.playAngle(30))
        XCTAssertNil(service.state.angle)
        XCTAssertNotNil(service.state.error)
    }

    private func makeOutputs() -> [SignalMode: FakeSignalOutput] {
        Dictionary(uniqueKeysWithValues: SignalMode.allCases.map { ($0, FakeSignalOutput()) })
    }
}

@MainActor
private final class FakeSignalOutput: SignalOutput {
    @Published var state = SignalPlaybackState(status: "ready")
    var statePublisher: AnyPublisher<SignalPlaybackState, Never> { $state.eraseToAnyPublisher() }
    var angles: [Double] = []
    var resetCount = 0
    var stopCount = 0
    var acceptsPlayback = true
    var speechStyle: SpeechStyle = .angle
    func setSpeechStyle(_ style: SpeechStyle) { stop(); speechStyle = style }
    func prepare() { state = .init(status: "ready") }
    func playAngle(_ signedDegrees: Double, configuration: HapticConfiguration?) -> Bool {
        angles.append(signedDegrees)
        state = acceptsPlayback ? .init(label: "angle", angle: signedDegrees, status: "playing")
            : .init(status: "failed", error: "output unavailable")
        return acceptsPlayback
    }
    func playReset() -> Bool {
        resetCount += 1
        state = .init(label: "reset", status: "playing")
        return true
    }
    func stop() { stopCount += 1; state = .init(status: "stopped") }
}

final class AudioCueTests: XCTestCase {
    func testSixAnglesHaveUniqueSpeechAndBeepCodes() throws {
        var speech = Set<String>()
        var beep = Set<String>()
        for angle in [-90, -60, -30, 30, 60, 90] {
            let cue = try XCTUnwrap(AudioCue.angle(Double(angle)))
            XCTAssertEqual(cue.speech, "\(angle < 0 ? "왼쪽" : "오른쪽") \(abs(angle))도")
            XCTAssertEqual(cue.frequency, angle < 0 ? 440 : 880)
            XCTAssertEqual(cue.count, abs(angle) == 30 ? 1 : abs(angle) == 60 ? 2 : 3)
            speech.insert(cue.speech)
            beep.insert(cue.beepDescription)
        }
        XCTAssertEqual(speech.count, 6)
        XCTAssertEqual(beep.count, 6)
        XCTAssertEqual(AudioCue.reset.speech, "기준 방향을 0도로 설정했어요")
        XCTAssertEqual(AudioCue.reset.frequency, 660)
        XCTAssertEqual(AudioCue.reset.duration, 0.5)
    }

    func testUnsupportedAndNonFiniteAnglesDoNotProduceSounds() {
        for angle in [13.0, 45, 181, 360, .nan, .infinity, -.infinity] {
            XCTAssertNil(AudioCue.angle(angle))
        }
    }

    func testEveryWaveDecodesAsMonoAndHasExpectedDuration() throws {
        let cues = try [-90, -60, -30, 30, 60, 90].map { try XCTUnwrap(AudioCue.angle(Double($0))) } + [.reset]
        for cue in cues {
            let player = try AVAudioPlayer(data: cue.waveData(), fileTypeHint: AVFileType.wav.rawValue)
            XCTAssertEqual(player.numberOfChannels, 1)
            XCTAssertEqual(player.duration, cue.duration, accuracy: 0.001)
        }
    }

    func testBeepWaveHasSilenceBetweenPulsesAndDoesNotClip() throws {
        let cue = try XCTUnwrap(AudioCue.angle(90))
        let data = cue.waveData()
        let samples: [Int16] = stride(from: 44, to: data.count, by: 2).map {
            Int16(bitPattern: UInt16(data[$0]) | UInt16(data[$0 + 1]) << 8)
        }
        func peak(from start: Double, to end: Double) -> Int {
            samples[Int(start * 44_100)..<Int(end * 44_100)].map { abs(Int($0)) }.max() ?? 0
        }
        XCTAssertGreaterThan(peak(from: 0.02, to: 0.14), 5_000)
        XCTAssertEqual(peak(from: 0.17, to: 0.27), 0)
        XCTAssertGreaterThan(peak(from: 0.30, to: 0.42), 5_000)
        XCTAssertEqual(peak(from: 0.45, to: 0.55), 0)
        XCTAssertGreaterThan(peak(from: 0.58, to: 0.70), 5_000)
        XCTAssertLessThan(samples.map { abs(Int($0)) }.max() ?? 0, 12_000)
    }
}


@MainActor
final class ClockSignalTests: XCTestCase {
    func testAllTwelveDirectionsHaveDistinctSpeechAndBeepCodes() throws {
        var angleSpeech = Set<String>()
        var clockSpeech = Set<String>()
        var beep = Set<String>()
        for (index, angle) in DirectionReference.signedLandmarks.enumerated() {
            let cue = try XCTUnwrap(AudioCue.angle(Double(angle)))
            let clock = try XCTUnwrap(AudioCue.angle(Double(angle), speechStyle: .clock))
            XCTAssertEqual(clock.speech, "\(index == 0 ? 12 : index)시 방향")
            angleSpeech.insert(cue.speech)
            clockSpeech.insert(clock.speech)
            beep.insert(cue.beepDescription)
        }
        XCTAssertEqual(angleSpeech.count, 12)
        XCTAssertEqual(clockSpeech.count, 12)
        XCTAssertEqual(beep.count, 12)
        XCTAssertEqual(AudioCue.angle(-180)?.speech, "뒤쪽 180도")
        XCTAssertEqual(AudioCue.angle(0)?.speech, "정면")
        XCTAssertEqual(AudioCue.reset(style: .clock).speech, "현재 방향을 12시로 설정했어요")
        XCTAssertEqual(DirectionDisplayMode.angle.value(-30), "330°")
        XCTAssertEqual(DirectionDisplayMode.angle.value(359.9), "0°")
        XCTAssertEqual(DirectionDisplayMode.clock.value(180), "6시")
    }

    func testLegacyBoth45DegreeSettingsMigrateAndNewChoicesPersistIndependently() throws {
        let suite = "ClockSettings.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let payload = Data(#"{"schemaVersion":2,"signalMode":"speech","angles":{"-45":{"enabled":false,"configuration":{"preset":"long","intensity":0.4,"sharpness":0.2}},"45":{"enabled":true,"configuration":{"preset":"double","intensity":0.6,"sharpness":0.3}}}}"#.utf8)
        let key = "orientationHaptics.angleSettings"
        defaults.set(payload, forKey: key)
        let store = HapticSettingsStore(defaults: defaults)
        XCTAssertEqual(defaults.data(forKey: key), payload, "Reading migration must preserve original bytes.")
        XCTAssertEqual(store.signalMode, .speech)
        XCTAssertFalse(store.isEnabled(-60))
        XCTAssertEqual(store.configuration(for: -60).preset, .long)
        XCTAssertEqual(store.configuration(for: 60).preset, .double)
        XCTAssertNil(store.settings[45])
        store.setDisplayMode(.clock)
        XCTAssertEqual(store.speechStyle, .angle)
        store.setSpeechStyle(.clock)
        store.setConfiguration(.init(preset: .accelerating, intensity: 0.8, sharpness: 0.6), for: 180)
        let restored = HapticSettingsStore(defaults: defaults)
        XCTAssertEqual(restored.displayMode, .clock)
        XCTAssertEqual(restored.speechStyle, .clock)
        XCTAssertEqual(restored.configuration(for: 180).preset, .accelerating)
        XCTAssertEqual(restored.settings, store.settings)
    }

    func testSpeechStyleRoutesToSpeechOnlyAndCancelsPriorSpeech() throws {
        let outputs = Dictionary(uniqueKeysWithValues: SignalMode.allCases.map { ($0, FakeSignalOutput()) })
        let service = SignalService(mode: .speech, outputs: outputs)
        service.playAngle(30)
        service.setSpeechStyle(.clock)
        XCTAssertEqual(outputs[.speech]?.speechStyle, .clock)
        XCTAssertEqual(outputs[.speech]?.stopCount, 1)
        XCTAssertEqual(outputs[.haptic]?.stopCount, 0)
        XCTAssertEqual(outputs[.beep]?.stopCount, 0)
        XCTAssertEqual(service.description(for: 90, configuration: .init()), "3시 방향")
        service.setSpeechStyle(.clock)
        XCTAssertEqual(outputs[.speech]?.stopCount, 1)
    }

    func testLengthPatternsKeepOrderAndGapAndRespectCustomStrength() {
        let variants: [(HapticConfiguration.Preset, [Double])] = [
            (.shortShort, [0.1, 0.1]), (.longLong, [0.35, 0.35]),
            (.longShort, [0.35, 0.1]), (.shortLong, [0.1, 0.35])
        ]
        for (preset, lengths) in variants {
            let pulses = HapticService.configuredEvents(isLeft: false, magnitude: 30,
                configuration: .init(preset: preset, intensity: 0.6, sharpness: 0.4))
            XCTAssertEqual(pulses.map(\.duration), lengths)
            XCTAssertEqual(pulses[1].time - pulses[0].duration, 0.2, accuracy: 0.0001)
            XCTAssertTrue(pulses.allSatisfy { $0.intensity == 0.6 && $0.sharpness == 0.4 })
        }
    }

    func testSpeedPatternsUseEqualPulsesAndDistinctSpacing() {
        let variants: [(HapticConfiguration.Preset, [Double])] = [
            (.fast, [0.12, 0.12]), (.slow, [0.5, 0.5]),
            (.accelerating, [0.5, 0.12]), (.decelerating, [0.12, 0.5])
        ]
        for (preset, gaps) in variants {
            let pulses = HapticService.configuredEvents(isLeft: false, magnitude: 180,
                configuration: .init(preset: preset))
            XCTAssertEqual(pulses.count, 3)
            XCTAssertEqual(pulses.map(\.duration), [0.065, 0.065, 0.065])
            for index in 0..<2 {
                XCTAssertEqual(pulses[index + 1].time - pulses[index].time - pulses[index].duration,
                               gaps[index], accuracy: 0.0001)
            }
        }
    }
}
