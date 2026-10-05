import Foundation

public enum AppAppearance: String, CaseIterable, Codable, Identifiable, Sendable {
    case system, light, dark
    public var id: String { rawValue }
    public var title: String {
        switch self { case .system: return "시스템 설정"; case .light: return "라이트"; case .dark: return "다크" }
    }
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public var gain = 1.0
    public var preparationSeconds = 3
    public var keepAwake = true
    public var successSound = true
    public var appearance: AppAppearance = .system
    public init() {}
    private enum CodingKeys: String, CodingKey { case gain, preparationSeconds, keepAwake, successSound, appearance }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        gain = try values.decodeIfPresent(Double.self, forKey: .gain) ?? 1
        preparationSeconds = try values.decodeIfPresent(Int.self, forKey: .preparationSeconds) ?? 3
        keepAwake = try values.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? true
        successSound = try values.decodeIfPresent(Bool.self, forKey: .successSound) ?? true
        appearance = try values.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
    }
    public var validated: Self {
        var copy = self
        copy.gain = gain.isFinite ? min(1, max(0.2, gain)) : 1
        copy.preparationSeconds = min(10, max(1, preparationSeconds))
        return copy
    }
}

/// Independent random draws: the last trial never makes the next direction predictable.
public struct RandomDirectionSource {
    private var generator: SeededGenerator
    public init(seed: UInt64) { generator = SeededGenerator(seed: seed) }
    public mutating func next() -> Direction { Direction.allCases.randomElement(using: &generator)! }
}
