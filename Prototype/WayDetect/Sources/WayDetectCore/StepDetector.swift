import Foundation

/// Waist-mounted IMU step ESTIMATE, independent of Apple's delayed pedometer.
/// Filters vertical user acceleration, requires an up/down cycle and plausible cadence.
/// The first two cycles are confirmed together; isolated bumps do not count.
public struct StepDetector: Sendable {
    private var lastTime: Double?
    private var smooth = 0.0
    private var bias = 0.0
    private var peakTime: Double?
    private var previousCandidate: Double?
    private var cadenceConfirmed = false
    public init() {}
    public mutating func reset() { self = Self() }
    public mutating func receive(_ sample: MotionObservation) -> [Double] {
        guard sample.isValid, sample.acceleration < 1.2, sample.rotationRate < 100 else { reset(); return [] }
        if let lastTime, sample.time <= lastTime { return [] }
        let dt = lastTime.map { sample.time - $0 } ?? 0.02
        if dt > 0.2 { reset() }
        lastTime = sample.time
        let interval = min(0.1, dt)
        bias += (interval / (1.5 + interval)) * (sample.verticalAcceleration - bias)
        smooth += (interval / (0.035 + interval)) * (sample.verticalAcceleration - bias - smooth)
        if let peakTime, sample.time - peakTime > 0.8 { self.peakTime = nil }
        if smooth >= 0.065 && peakTime == nil { peakTime = sample.time }
        guard let peak = peakTime, smooth <= -0.035, sample.time - peak >= 0.08 else { return [] }
        peakTime = nil
        let candidate = peak
        guard let previous = previousCandidate else {
            previousCandidate = candidate; cadenceConfirmed = false; return []
        }
        let period = candidate - previous
        guard period >= 0.28 else { return [] }
        previousCandidate = candidate
        guard period <= 1.6 else { cadenceConfirmed = false; return [] }
        if cadenceConfirmed { return [candidate] }
        cadenceConfirmed = true
        return [previous, candidate]
    }
}

/// Same-origin cumulative iOS samples from live delivery and history queries are NEVER added.
public struct PedometerCounter: Sendable {
    public private(set) var total = 0
    public init() {}
    @discardableResult public mutating func merge(_ cumulative: Int) -> Bool {
        guard cumulative >= total else { return false }
        total = cumulative; return true
    }
}
