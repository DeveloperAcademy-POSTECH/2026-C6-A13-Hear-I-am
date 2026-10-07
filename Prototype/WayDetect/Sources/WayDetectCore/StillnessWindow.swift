import Foundation

/// Consecutive stationary SENSOR time, never elapsed wall time alone.
/// A turn, new step, invalid sample, or sample gap starts a new hold.
struct StillnessWindow {
    private var points: [MotionObservation] = []
    mutating func reset() { points.removeAll(keepingCapacity: true) }
    mutating func append(_ sample: MotionObservation) {
        guard sample.isValid, sample.rotationRate <= 8, sample.acceleration <= 0.08 else { reset(); return }
        if let last = points.last {
            guard sample.time > last.time else { return }
            if sample.time - last.time > 0.2 { reset() }
        }
        if let first = points.first, abs(Angles.signed(sample.heading - first.heading)) > 4 { reset() }
        points.append(sample)
        if points.count > 100 { points.removeFirst(points.count - 100) }
    }
    var duration: Double { guard let first = points.first, let last = points.last else { return 0 }; return last.time - first.time }
    func ready(for seconds: Double) -> Bool { points.count >= 10 && duration + 1e-9 >= seconds }
    var mean: Double {
        guard let first = points.first else { return 0 }
        return first.heading + points.reduce(0) { $0 + Angles.signed($1.heading - first.heading) } / Double(points.count)
    }
}
