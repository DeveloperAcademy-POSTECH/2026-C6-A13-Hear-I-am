/// Bounded retries for one input outage. A successful final result or a quiet interval
/// resets the budget; reconnecting the audio engine alone does not.
public struct VoiceInputRecoveryPolicy: Sendable {
    private var attempts = 0
    private var lastFailure: Double?
    public init() {}
    public mutating func nextDelay(at time: Double) -> Double? {
        if let previous = lastFailure, time - previous >= 30 { attempts = 0 }
        lastFailure = time
        guard attempts < 3 else { return nil }
        let delay = [0.5, 1.0, 2.0][attempts]
        attempts += 1
        return delay
    }
    public mutating func reset() { attempts = 0; lastFailure = nil }
}
