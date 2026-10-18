import Foundation

/// App-wide interaction preference, separate from a saved stage's movement settings.
public struct GuidanceInteractionSettings: Sendable {
    public static let advanceDuringSpeechKey = "guidance.advanceDuringSpeech"
    public let advanceDuringSpeech: Bool
    public init(defaults: UserDefaults = .standard) {
        advanceDuringSpeech=defaults.bool(forKey:Self.advanceDuringSpeechKey)
    }
    /// Only bypasses narration waiting. Callers must also enforce their tracking/phase guards.
    public func canAdvanceInstruction(done: Bool, speaking: Bool, audioFailed: Bool) -> Bool {
        !audioFailed && (advanceDuringSpeech || (done && !speaking))
    }
}
