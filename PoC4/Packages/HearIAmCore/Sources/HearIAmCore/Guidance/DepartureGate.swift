import Foundation

/// Readiness requires fresh, consecutive samples; a single matching frame never starts guidance.
public struct DepartureGate: Sendable {
    private var since: Double?
    private var last: Double?
    public init() {}
    public mutating func reset() { since=nil; last=nil }
    public mutating func observe(time: Double, eligible: Bool) -> Bool {
        guard time.isFinite, eligible else { reset(); return false }
        if let last, time <= last { return false }
        if let last, time-last > 0.5 { since=nil }
        last=time
        if since == nil { since=time }
        return time-(since ?? time) >= 1.0
    }
}
