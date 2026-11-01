import Foundation

/// A visual envelope, not a speech detector. Silent PCM remains valid microphone input.
/// The owner provides RMS from the existing capture tap and synchronizes access.
public struct VoiceInputLevelMeter: Sendable {
    public private(set) var level: Double = 0
    private var lastSampleTime: Double?
    private var lastEmissionTime: Double?

    public init() {}

    /// Returns at most 20 display updates per second; invalid/out-of-order samples are ignored.
    public mutating func ingest(rms: Double, at time: Double) -> Double? {
        guard rms.isFinite, rms >= 0, time.isFinite, time >= 0 else { return nil }
        if let previous = lastSampleTime, time <= previous { return nil }
        let elapsed = lastSampleTime.map { time - $0 } ?? 0.05
        if elapsed > 1 { level = 0 }
        lastSampleTime = time
        // Below -55 dBFS is visually quiet; ordinary speech expands the ribbons gradually.
        let decibels = 20 * log10(max(rms, 0.000001))
        let target = pow(min(1, max(0, (decibels + 55) / 43)), 1.4)
        let response = target > level ? 0.045 : 0.18
        level += (target - level) * (1 - exp(-min(elapsed, 0.2) / response))
        if level < 0.002 { level = 0 }
        guard lastEmissionTime.map({ time - $0 >= 0.05 - 1e-9 }) ?? true else { return nil }
        lastEmissionTime = time
        return level
    }

    public mutating func reset() { self = Self() }
}
