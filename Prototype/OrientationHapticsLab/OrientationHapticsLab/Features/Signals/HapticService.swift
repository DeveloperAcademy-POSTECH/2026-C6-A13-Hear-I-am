import Combine
import CoreHaptics
import UIKit

/// Saved per angle by the app. Values remain valid after decoding and UI edits.
struct HapticConfiguration: Codable, Equatable, Sendable {
    enum Preset: String, Codable, CaseIterable, Identifiable, Sendable {
        case directional
        case single
        case double
        case triple
        case long

        var id: String { rawValue }

        var title: String {
            switch self {
            case .directional: "방향·각도 기본 리듬"
            case .single: "짧게 한 번"
            case .double: "짧게 두 번"
            case .triple: "짧게 세 번"
            case .long: "길게 한 번"
            }
        }
    }

    var preset: Preset
    var intensity: Double {
        didSet { intensity = Self.bounded(intensity, fallback: 0.9) }
    }
    var sharpness: Double {
        didSet { sharpness = Self.bounded(sharpness, fallback: 0.8) }
    }

    init(preset: Preset = .directional, intensity: Double = 0.9, sharpness: Double = 0.8) {
        self.preset = preset
        self.intensity = Self.bounded(intensity, fallback: 0.9)
        self.sharpness = Self.bounded(sharpness, fallback: 0.8)
    }

    var describe: String {
        "\(preset.title) · 세기 \(Int((intensity * 100).rounded()))% · 선명도 \(Int((sharpness * 100).rounded()))%"
    }

    private enum CodingKeys: String, CodingKey { case preset, intensity, sharpness }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            preset: try values.decode(Preset.self, forKey: .preset),
            intensity: try values.decode(Double.self, forKey: .intensity),
            sharpness: try values.decode(Double.self, forKey: .sharpness)
        )
    }

    private static func bounded(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : fallback
    }
}

/// Queues a signal without waiting for the hardware. Published playback begins on driver acceptance.
@MainActor
final class HapticService: ObservableObject {
    let supportsHaptics: Bool
    @Published private(set) var isReady = false
    @Published private(set) var status = "진동 준비 중"
    @Published private(set) var currentlyPlaying: String?
    @Published private(set) var currentlyPlayingAngle: Double?
    @Published private(set) var lastError: String?
    static let resetPatternDescription = "부드러운 긴 진동 두 번"

    private let driver: any HapticDriving
    private var revision: UInt = 0
    private var pendingLabel: String?
    private var pendingAngle: Double?
    private var timeout: Task<Void, Never>?
    private var isForeground: Bool
    private let responseTimeout: Duration
    private var subscriptions = Set<AnyCancellable>()

    init(driver: any HapticDriving = HapticEngineDriver(), supportsHaptics: Bool? = nil,
         isForeground: Bool? = nil, responseTimeout: Duration = .seconds(3)) {
        self.driver = driver
        self.supportsHaptics = supportsHaptics ?? CHHapticEngine.capabilitiesForHardware().supportsHaptics
        self.isForeground = isForeground ?? (UIApplication.shared.applicationState == .active)
        self.responseTimeout = responseTimeout
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { @Sendable [weak self] _ in Task { @MainActor [weak self] in self?.suspend() } }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { @Sendable [weak self] _ in Task { @MainActor [weak self] in self?.isForeground = true } }
            .store(in: &subscriptions)
        if !self.supportsHaptics { status = "이 기기는 진동을 지원하지 않아요." }
    }

    func prepare() {
        guard supportsHaptics, isForeground, pendingLabel == nil, !isReady else { return }
        revision &+= 1
        let token = revision
        status = "진동 준비 중"
        armTimeout(token)
        let callback = makeReply()
        Task { await driver.prepare(revision: token, reply: callback) }
    }

    @discardableResult
    func playAngle(_ signedDegrees: Double, configuration: HapticConfiguration? = nil) -> Bool {
        guard let magnitude = Self.supportedMagnitude(signedDegrees) else {
            stop()
            lastError = "지원하는 각도는 왼쪽·오른쪽 30°, 45°, 90°입니다."
            return false
        }
        return play(events: Self.configuredEvents(isLeft: signedDegrees < 0, magnitude: magnitude,
                   configuration: configuration ?? Self.defaultConfiguration(for: signedDegrees)),
                    label: "\(signedDegrees < 0 ? "왼쪽" : "오른쪽") \(magnitude)°", angle: signedDegrees)
    }

    @discardableResult
    func playReset() -> Bool {
        play(events: [Self.pulse(at: 0, duration: 0.17, intensity: 0.85, sharpness: 0.2),
                      Self.pulse(at: 0.30, duration: 0.17, intensity: 0.85, sharpness: 0.2)],
             label: "기준 방향 리셋")
    }

    /// Cancel only the current signal; normal resets must reuse the prepared engine.
    func stop() { cancel(suspend: false) }

    private func suspend() {
        isForeground = false
        cancel(suspend: true)
    }

    private func cancel(suspend: Bool) {
        revision &+= 1
        let token = revision
        clearPlayback()
        if suspend { isReady = false }
        status = supportsHaptics ? "진동 중지됨" : "이 기기는 진동을 지원하지 않아요."
        Task { await driver.cancel(revision: token, suspend: suspend) }
    }

    private func play(events: [HapticPulse], label: String, angle: Double? = nil) -> Bool {
        guard supportsHaptics, isForeground else {
            status = supportsHaptics ? "진동 보류 · 앱을 화면에 열어 주세요" : "진동 미지원 · 실제 아이폰에서 확인 필요"
            return false
        }
        revision &+= 1
        let token = revision
        clearPlayback()
        pendingLabel = label
        pendingAngle = angle
        lastError = nil
        status = "진동 신호 준비 중"
        armTimeout(token)
        let callback = makeReply()
        Task { await driver.play(events, revision: token, reply: callback) }
        return true
    }

    private func makeReply() -> HapticReply {
        { [weak self] token, event in
            Task { @MainActor [weak self] in self?.receive(token: token, event: event) }
        }
    }

    private func receive(token: UInt, event: HapticDriverEvent) {
        guard token == revision else { return }
        switch event {
        case .ready:
            isReady = true
            if pendingLabel == nil { timeout?.cancel(); status = "진동 준비됨" }
        case .playing:
            isReady = true
            currentlyPlaying = pendingLabel
            currentlyPlayingAngle = pendingAngle
            status = "진동 재생 중"
        case .finished:
            clearPlayback()
            status = "진동 준비됨"
        case .failed(let message):
            clearPlayback()
            isReady = false
            lastError = message
            status = "진동 재생 실패"
        }
    }

    private func armTimeout(_ token: UInt) {
        timeout?.cancel()
        timeout = Task { [weak self, responseTimeout] in
            try? await Task.sleep(for: responseTimeout)
            guard !Task.isCancelled, let self, self.revision == token else { return }
            self.cancel(suspend: true)
            self.lastError = "진동 장치의 응답이 늦어 신호를 취소했어요. 측정은 계속됩니다."
            self.status = "진동 응답 지연"
        }
    }

    private func clearPlayback() {
        timeout?.cancel()
        timeout = nil
        pendingLabel = nil
        pendingAngle = nil
        currentlyPlaying = nil
        currentlyPlayingAngle = nil
    }

    static func defaultConfiguration(for signedDegrees: Double) -> HapticConfiguration {
        let magnitude = supportedMagnitude(signedDegrees)
        let intensity = magnitude == 30 ? 0.85 : magnitude == 45 ? 0.92 : 1.0
        return HapticConfiguration(preset: .directional, intensity: intensity, sharpness: 0.8)
    }

    static func patternDescription(for signedDegrees: Double, configuration: HapticConfiguration? = nil) -> String {
        if let configuration, configuration.preset != .directional {
            return configuration.describe
        }
        guard let magnitude = supportedMagnitude(signedDegrees) else { return "지원하지 않는 각도" }
        let prefix = signedDegrees < 0 ? "긴 진동 한 번" : "짧은 진동 두 번"
        let count = magnitude == 30 ? "한 번" : magnitude == 45 ? "두 번" : "세 번"
        return "\(prefix) 뒤, 짧은 진동 \(count)"
    }

    private static func supportedMagnitude(_ value: Double) -> Int? {
        guard value.isFinite else { return nil }
        return [30, 45, 90].first { abs(abs(value) - Double($0)) < 0.001 }
    }

    private static func configuredEvents(
        isLeft: Bool,
        magnitude: Int,
        configuration: HapticConfiguration
    ) -> [HapticPulse] {
        let intensity = Float(configuration.intensity)
        let sharpness = Float(configuration.sharpness)
        switch configuration.preset {
        case .directional:
            var events: [HapticPulse]
            if isLeft {
                events = [pulse(at: 0, duration: 0.10, intensity: intensity, sharpness: sharpness * 0.5)]
            } else {
                events = [
                    pulse(at: 0, duration: 0.03, intensity: intensity, sharpness: sharpness),
                    pulse(at: 0.06, duration: 0.03, intensity: intensity, sharpness: sharpness)
                ]
            }
            let count = magnitude == 30 ? 1 : magnitude == 45 ? 2 : 3
            for index in 0..<count {
                events.append(pulse(
                    at: 0.16 + Double(index) * 0.09,
                    duration: 0.035,
                    intensity: intensity,
                    sharpness: sharpness
                ))
            }
            return events
        case .single:
            return [pulse(at: 0, duration: 0.065, intensity: intensity, sharpness: sharpness)]
        case .double, .triple:
            let count = configuration.preset == .double ? 2 : 3
            return (0..<count).map { index in
                pulse(at: Double(index) * 0.13, duration: 0.065, intensity: intensity, sharpness: sharpness)
            }
        case .long:
            return [pulse(at: 0, duration: 0.30, intensity: intensity, sharpness: sharpness)]
        }
    }

    private static func pulse(at time: TimeInterval, duration: TimeInterval, intensity: Float, sharpness: Float) -> HapticPulse {
        HapticPulse(time: time, duration: duration, intensity: intensity, sharpness: sharpness)
    }
}
