import Foundation

/// Confirms that a new recognition turn is receiving microphone PCM, including silence.
/// A recognizer task or a running engine alone does not establish input readiness.
/// The owner must synchronize access and reject callbacks from retired turns.
public struct VoiceMicrophoneReadiness: Sendable {
    public private(set) var isReady = false
    public private(set) var lastBufferTime: Double?
    private var accumulatedDuration: Double = 0

    public init() {}

    /// Returns true once per reset, after at least 100 ms of valid input has arrived.
    /// Empty/invalid buffers and timestamps older than the last accepted buffer are ignored.
    @discardableResult
    public mutating func ingest(frameCount: Int, sampleRate: Double, channelCount: Int,
                                at time: Double) -> Bool {
        guard frameCount > 0, channelCount > 0, sampleRate.isFinite, sampleRate > 0,
              time.isFinite, time >= 0 else { return false }
        if let lastBufferTime, time < lastBufferTime { return false }
        let duration = Double(frameCount) / sampleRate
        guard duration.isFinite, duration > 0 else { return false }
        if let lastBufferTime, time - lastBufferTime > 1, !isReady {
            accumulatedDuration = 0
        }
        lastBufferTime = time
        guard !isReady else { return false }
        accumulatedDuration += duration
        // Permit only floating-point rounding error at the 100 ms boundary.
        guard accumulatedDuration + 1e-9 >= 0.1 else { return false }
        isReady = true
        return true
    }

    /// No first buffer is handled by the owner's startup deadline, not by this watchdog.
    public func isStalled(at time: Double, timeout: Double = 2) -> Bool {
        guard let lastBufferTime, time.isFinite, timeout.isFinite, timeout > 0,
              time >= lastBufferTime else { return false }
        return time - lastBufferTime >= timeout
    }

    /// Start each recognition turn with a fresh gate; an earlier turn cannot make it ready.
    public mutating func reset() { self = Self() }
}
