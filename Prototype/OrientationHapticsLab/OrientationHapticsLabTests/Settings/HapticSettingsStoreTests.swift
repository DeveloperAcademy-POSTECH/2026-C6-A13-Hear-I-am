import Foundation
import OrientationCore
import XCTest
@testable import OrientationHapticsLab

/// These tests exercise the app's real stores. Every preferences suite and archive path
/// is unique to a test and removed afterward; app-standard settings/logs are never used.
@MainActor
final class HapticSettingsStoreTests: XCTestCase {
    func testFreshStoreHasAllSixDefaultSignalsEnabled() throws {
        try withIsolatedDefaults { defaults, key in
            let store = HapticSettingsStore(defaults: defaults, storageKey: key)
            assertDefaults(store)
            XCTAssertNil(store.errorMessage)
            XCTAssertNil(defaults.object(forKey: key), "Reading defaults must not write them to disk.")
        }
    }

    func testPerAngleSettingsSurviveRecreation() throws {
        try withIsolatedDefaults { defaults, key in
            let store = HapticSettingsStore(defaults: defaults, storageKey: key)
            let presets: [HapticConfiguration.Preset] = [.long, .single, .double, .triple, .directional, .long]
            for (index, angle) in HapticSettingsStore.supportedAngles.enumerated() {
                store.setConfiguration(HapticConfiguration(
                    preset: presets[index],
                    intensity: 0.2 + Double(index) * 0.1,
                    sharpness: Double(index) * 0.15
                ), for: angle)
                store.setEnabled(angle, enabled: index.isMultiple(of: 2))
            }
            let expected = store.settings
            XCTAssertNotNil(defaults.data(forKey: key))
            let restored = HapticSettingsStore(defaults: defaults, storageKey: key)
            XCTAssertEqual(restored.settings, expected)
            XCTAssertEqual(restored.enabledAngles, [-90, -30, 45])
            XCTAssertNil(restored.errorMessage)
        }
    }

    func testChangingOneAnglePreservesEveryOtherAngleAndResetKeepsItsToggle() throws {
        try withIsolatedDefaults { defaults, key in
            let store = HapticSettingsStore(defaults: defaults, storageKey: key)
            let initial = store.settings
            let custom = HapticConfiguration(preset: .triple, intensity: 0.4, sharpness: 0.15)
            store.setConfiguration(custom, for: -30)
            store.setEnabled(-30, enabled: false)
            XCTAssertEqual(store.configuration(for: -30), custom)
            XCTAssertFalse(store.isEnabled(-30))
            for angle in HapticSettingsStore.supportedAngles where angle != -30 {
                XCTAssertEqual(store.settings[angle], initial[angle], "Unexpected edit of \(angle)°")
            }
            store.resetConfiguration(for: -30)
            XCTAssertEqual(store.configuration(for: -30), HapticService.defaultConfiguration(for: -30))
            XCTAssertFalse(store.isEnabled(-30), "Resetting a rhythm must preserve its enabled switch.")
            let restored = HapticSettingsStore(defaults: defaults, storageKey: key)
            XCTAssertEqual(restored.settings, store.settings)
        }
    }

    func testMalformedPayloadsFallBackAndCanBeReplacedByANewEdit() throws {
        try withIsolatedDefaults { defaults, key in
            let invalidValues: [Any] = [
                "unexpected preferences type",
                Data("not JSON".utf8),
                Data(repeating: 0x20, count: 65_537),
                Data(#"{"schemaVersion":1,"angles":{"30":{"enabled":true,"configuration":{"preset":"unknown","intensity":0.8,"sharpness":0.5}}}}"#.utf8)
            ]
            for value in invalidValues {
                defaults.set(value, forKey: key)
                let store = HapticSettingsStore(defaults: defaults, storageKey: key)
                assertDefaults(store)
                XCTAssertNotNil(store.errorMessage)
                store.setEnabled(-45, enabled: false)
                XCTAssertNil(store.errorMessage)
                let restored = HapticSettingsStore(defaults: defaults, storageKey: key)
                XCTAssertFalse(restored.isEnabled(-45))
                XCTAssertNil(restored.errorMessage)
            }
        }
    }

    func testFutureSchemaFallsBackWithoutOverwritingSavedPayloadOnRead() throws {
        try withIsolatedDefaults { defaults, key in
            let payload = Data(#"{"schemaVersion":99,"angles":{"30":{"enabled":false,"configuration":{"preset":"long","intensity":0.3,"sharpness":0.2}}}}"#.utf8)
            defaults.set(payload, forKey: key)
            let store = HapticSettingsStore(defaults: defaults, storageKey: key)
            assertDefaults(store)
            XCTAssertNotNil(store.errorMessage)
            XCTAssertEqual(defaults.data(forKey: key), payload)
        }
    }

    func testPartialPayloadRestoresKnownAnglesAndClampsDecodedParameters() throws {
        try withIsolatedDefaults { defaults, key in
            let payload = Data(#"{"schemaVersion":1,"angles":{"30":{"enabled":false,"configuration":{"preset":"long","intensity":-99,"sharpness":99}},"-45":{"enabled":true,"configuration":{"preset":"double","intensity":999,"sharpness":-1}},"13":{"enabled":true,"configuration":{"preset":"single","intensity":0.5,"sharpness":0.5}}}}"#.utf8)
            defaults.set(payload, forKey: key)
            let store = HapticSettingsStore(defaults: defaults, storageKey: key)
            XCTAssertNil(store.errorMessage)
            XCTAssertFalse(store.isEnabled(30))
            XCTAssertEqual(store.configuration(for: 30).preset, .long)
            XCTAssertEqual(store.configuration(for: 30).intensity, 0.1)
            XCTAssertEqual(store.configuration(for: 30).sharpness, 1)
            XCTAssertEqual(store.configuration(for: -45).preset, .double)
            XCTAssertEqual(store.configuration(for: -45).intensity, 1)
            XCTAssertEqual(store.configuration(for: -45).sharpness, 0)
            XCTAssertEqual(store.configuration(for: 90), HapticService.defaultConfiguration(for: 90))
            XCTAssertTrue(store.isEnabled(90))
            XCTAssertNil(store.settings[13])
            XCTAssertFalse(store.isEnabled(13))

            // Any subsequent edit persists the bounded representation, not the malformed values.
            store.setEnabled(90, enabled: false)
            let restored = HapticSettingsStore(defaults: defaults, storageKey: key)
            XCTAssertEqual(restored.settings, store.settings)
        }
    }

    func testUnknownAngleEditsDoNotMutateSupportedSettings() throws {
        try withIsolatedDefaults { defaults, key in
            let store = HapticSettingsStore(defaults: defaults, storageKey: key)
            let before = store.settings
            store.setEnabled(13, enabled: true)
            store.setConfiguration(.init(preset: .long), for: 13)
            store.resetConfiguration(for: 13)
            XCTAssertEqual(store.settings, before)
            XCTAssertNil(defaults.object(forKey: key))
        }
    }

    func testConfigurationBoundsRemainEncodableAfterInvalidInputAndMutation() throws {
        let decoded = try JSONDecoder().decode(HapticConfiguration.self, from:
            Data(#"{"preset":"long","intensity":-2,"sharpness":4}"#.utf8))
        XCTAssertEqual(decoded.intensity, 0)
        XCTAssertEqual(decoded.sharpness, 1)
        XCTAssertEqual(decoded.preset, .long)

        var configuration = HapticConfiguration(preset: .double, intensity: .nan, sharpness: .infinity)
        XCTAssertEqual(configuration.intensity, 0.9)
        XCTAssertEqual(configuration.sharpness, 0.8)
        configuration.intensity = -.infinity
        configuration.sharpness = .nan
        XCTAssertEqual(configuration.intensity, 0.9)
        XCTAssertEqual(configuration.sharpness, 0.8)
        let data = try JSONEncoder().encode(configuration)
        XCTAssertEqual(try JSONDecoder().decode(HapticConfiguration.self, from: data), configuration)
    }

    private func withIsolatedDefaults(_ body: (UserDefaults, String) throws -> Void) throws {
        let suite = "OrientationHapticsLabTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults, "settings-under-test")
    }

    private func assertDefaults(_ store: HapticSettingsStore, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Set(store.settings.keys), Set([-90, -45, -30, 30, 45, 90]), file: file, line: line)
        XCTAssertEqual(store.enabledAngles, Set([-90, -45, -30, 30, 45, 90]), file: file, line: line)
        for angle in HapticSettingsStore.supportedAngles {
            XCTAssertTrue(store.isEnabled(angle), file: file, line: line)
            XCTAssertEqual(store.configuration(for: angle),
                           HapticService.defaultConfiguration(for: Double(angle)), file: file, line: line)
        }
    }
}
