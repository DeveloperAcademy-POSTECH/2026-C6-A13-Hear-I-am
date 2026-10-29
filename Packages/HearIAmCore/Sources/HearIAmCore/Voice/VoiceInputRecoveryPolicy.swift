/// Bounded retries for a listening session. Elapsed time, an engine restart, and an
/// empty recognition result are not evidence that voice input has recovered.
public struct VoiceInputRecoveryPolicy: Sendable {
    private var attempts = 0

    public init() {}

    public mutating func nextDelay() -> Double? {
        guard attempts < 3 else { return nil }
        let delay = [0.5, 1.0, 2.0][attempts]
        attempts += 1
        return delay
    }

    /// Call only for a final recognizer result, never for a partial hypothesis.
    /// An empty/whitespace-only final result must not reopen an exhausted retry budget.
    public mutating func recordFinalRecognition(_ text: String) {
        guard text.contains(where: { !$0.isWhitespace }) else { return }
        attempts = 0
    }

    /// Begin a new explicitly requested listening session with a fresh retry budget.
    /// Do not call this when replacing the audio engine or rotating a recognition task.
    public mutating func reset() { attempts = 0 }
}
