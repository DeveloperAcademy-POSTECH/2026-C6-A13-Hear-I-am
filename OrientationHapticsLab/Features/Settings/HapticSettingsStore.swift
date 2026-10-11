import Combine
import Foundation
import OrientationCore

@MainActor
final class HapticSettingsStore: ObservableObject {
    struct AngleSetting: Codable, Equatable, Sendable {
        var enabled: Bool
        var configuration: HapticConfiguration
    }

    private struct Snapshot: Codable {
        let schemaVersion: Int
        let angles: [String: AngleSetting]
        let signalMode: String?
        let displayMode: String?
        let speechStyle: String?
    }

    static let supportedAngles = DirectionReference.signedLandmarks
    @Published private(set) var settings: [Int: AngleSetting]
    @Published private(set) var signalMode: SignalMode = .haptic
    @Published private(set) var displayMode: DirectionDisplayMode = .angle
    @Published private(set) var speechStyle: SpeechStyle = .angle
    @Published private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "orientationHaptics.angleSettings") {
        self.defaults = defaults
        self.storageKey = storageKey
        settings = Self.makeDefaults()
        load()
    }

    var enabledAngles: Set<Int> {
        Set(settings.filter { $0.value.enabled }.map(\.key))
    }

    func configuration(for angle: Int) -> HapticConfiguration {
        settings[angle]?.configuration ?? HapticService.defaultConfiguration(for: Double(angle))
    }

    func isEnabled(_ angle: Int) -> Bool {
        settings[angle]?.enabled ?? false
    }

    func setDisplayMode(_ mode: DirectionDisplayMode) {
        displayMode = mode
        save()
    }

    func setSpeechStyle(_ style: SpeechStyle) {
        speechStyle = style
        save()
    }

    func setSignalMode(_ mode: SignalMode) {
        signalMode = mode
        save()
    }

    func setEnabled(_ angle: Int, enabled: Bool) {
        guard var setting = settings[angle] else { return }
        setting.enabled = enabled
        settings[angle] = setting
        save()
    }

    func setConfiguration(_ configuration: HapticConfiguration, for angle: Int) {
        guard var setting = settings[angle] else { return }
        setting.configuration = Self.validated(configuration)
        settings[angle] = setting
        save()
    }

    func resetConfiguration(for angle: Int) {
        guard Self.supportedAngles.contains(angle) else { return }
        setConfiguration(HapticService.defaultConfiguration(for: Double(angle)), for: angle)
    }

    private func load() {
        guard let rawValue = defaults.object(forKey: storageKey) else { return }
        guard let data = rawValue as? Data, data.count <= 65_536 else {
            errorMessage = "저장된 신호 설정을 읽지 못해 기본값을 사용해요. 변경한 설정은 다시 저장됩니다."
            return
        }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            guard (1...3).contains(snapshot.schemaVersion) else {
                errorMessage = "이 버전에서 읽을 수 없는 신호 설정이에요. 기본값을 사용합니다."
                return
            }
            var restored = Self.makeDefaults()
            for angle in Self.supportedAngles {
                let legacy = snapshot.schemaVersion < 3 && abs(angle) == 60 ? (angle < 0 ? -45 : 45) : angle
                if var setting = snapshot.angles[String(angle)] ?? snapshot.angles[String(legacy)] {
                    setting.configuration = Self.validated(setting.configuration)
                    restored[angle] = setting
                }
            }
            settings = restored
            displayMode = snapshot.displayMode.flatMap(DirectionDisplayMode.init(rawValue:)) ?? .angle
            speechStyle = snapshot.speechStyle.flatMap(SpeechStyle.init(rawValue:)) ?? .angle
            signalMode = snapshot.signalMode.flatMap(SignalMode.init(rawValue:)) ?? .haptic
            if let savedMode = snapshot.signalMode, SignalMode(rawValue: savedMode) == nil {
                errorMessage = "저장된 신호 방식을 읽지 못해 진동을 사용해요. 각도별 설정은 유지됩니다."
            }
        } catch {
            errorMessage = "저장된 신호 설정을 읽지 못해 기본값을 사용해요. 변경한 설정은 다시 저장됩니다."
        }
    }

    private func save() {
        let snapshot = Snapshot(
            schemaVersion: 3,
            angles: Dictionary(uniqueKeysWithValues: settings.map { (String($0.key), $0.value) }),
            signalMode: signalMode.rawValue,
            displayMode: displayMode.rawValue,
            speechStyle: speechStyle.rawValue
        )
        do {
            defaults.set(try JSONEncoder().encode(snapshot), forKey: storageKey)
            errorMessage = nil
        } catch {
            errorMessage = "신호 설정을 저장하지 못했어요. 앱을 닫기 전에 다시 변경해 주세요."
        }
    }

    private static func makeDefaults() -> [Int: AngleSetting] {
        Dictionary(uniqueKeysWithValues: supportedAngles.map { angle in
            (angle, AngleSetting(enabled: true, configuration: HapticService.defaultConfiguration(for: Double(angle))))
        })
    }

    private static func validated(_ configuration: HapticConfiguration) -> HapticConfiguration {
        var result = HapticConfiguration(
            preset: configuration.preset,
            intensity: configuration.intensity,
            sharpness: configuration.sharpness
        )
        result.intensity = max(0.1, result.intensity)
        return result
    }
}
