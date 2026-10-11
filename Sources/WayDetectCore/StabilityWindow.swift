import Foundation

/// A short, recent rest check. This measures consistency, never absolute accuracy.
struct StabilityWindow {
    private var points: [MotionObservation] = []
    mutating func reset() { points.removeAll(keepingCapacity: true) }
    mutating func append(_ sample: MotionObservation) {
        guard sample.isValid else { reset(); return }
        if let last = points.last, sample.time - last.time > 0.25 { reset() }
        points.append(sample)
        points.removeAll { sample.time - $0.time > 1.15 }
    }
    var mean: Double {
        guard let first = points.first else { return 0 }
        return first.heading + points.reduce(0) { $0 + Angles.signed($1.heading - first.heading) } / Double(points.count)
    }
    var progress: Double {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return 0 }
        let differences = points.map { Angles.signed($0.heading - mean) }
        let spread = (differences.max() ?? 0) - (differences.min() ?? 0)
        let rate = sqrt(points.reduce(0) { $0 + $1.rotationRate * $1.rotationRate } / Double(points.count))
        let acceleration = sqrt(points.reduce(0) { $0 + $1.acceleration * $1.acceleration } / Double(points.count))
        guard spread <= 6, rate <= 15, acceleration <= 0.12 else { return 0 }
        return min(1, (last.time - first.time) / 1.0)
    }
    var ready: Bool { progress >= 1 && points.count >= 10 }
}
