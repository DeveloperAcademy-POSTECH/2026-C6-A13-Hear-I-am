import Foundation

/// Display-only gait timing. It neither changes the stored trajectory nor influences guidance.
public struct GuidanceWalkTimeline: Sendable {
    public struct Pose: Equatable, Sendable {
        public let distance: Double
        public let gaitDistance: Double
        public let strideScale: Double
        public let speed: Double
        public let blend: Double
    }
    private let replay: GuidanceReplay
    private let distances: [Double]
    private let gaitDistances: [Double]

    public init(replay: GuidanceReplay) {
        self.replay = replay
        var total = 0.0, gaitTotal = 0.0, distances = [Double](), gaitDistances = [Double]()
        for (index, sample) in replay.samples.enumerated() {
            if index > 0 {
                let previous = replay.samples[index - 1]
                if replay.connects(previous, sample), let a = previous.position, let b = sample.position {
                    let distance = a.distance(to: b), duration = sample.time - previous.time
                    // Subtle stationary AR jitter should not continuously cycle the legs.
                    if distance / duration >= 0.08 {
                        total += distance
                        gaitTotal += distance / Self.strideScale(speed: distance / duration)
                    }
                }
            }
            distances.append(total); gaitDistances.append(gaitTotal)
        }
        self.distances = distances; self.gaitDistances = gaitDistances
    }

    // Shorter steps at low speed keep the figure from performing an exaggerated, slow-motion stride.
    private static func strideScale(speed: Double) -> Double {
        let ratio = max(0, min(1, speed / 1.1166)) // Supplied clip: 1.349 m per 1.208 s cycle.
        return max(0.15, ratio * (1 + 0.25 * (1 - ratio)))
    }
    private func distance(at time: Double, values: [Double]? = nil) -> Double {
        let distances = values ?? self.distances
        guard let index = replay.index(at: time) else { return 0 }
        guard index + 1 < distances.count else { return distances[index] }
        let a = replay.samples[index], b = replay.samples[index + 1]
        guard replay.connects(a, b) else { return distances[index] }
        let fraction = max(0, min(1, (time - a.time) / (b.time - a.time)))
        return distances[index] + (distances[index + 1] - distances[index]) * fraction
    }

    /// Random access gives the same pose after a seek, pause, or playback-rate change.
    public func pose(at time: Double) -> Pose {
        guard time.isFinite else { return Pose(distance: 0, gaitDistance: 0, strideScale: 0.15, speed: 0, blend: 0) }
        let traveled = distance(at: time), gaitDistance = distance(at: time, values: gaitDistances)
        guard replay.pose(at: time) != nil else { return Pose(distance: traveled, gaitDistance: gaitDistance, strideScale: 0.15, speed: 0, blend: 0) }
        // A short symmetric window softens starts/stops without accumulating frame-dependent state.
        let window = 0.20
        let speed = max(0, (distance(at: min(replay.duration, time + window)) - distance(at: max(0, time - window))) / (2 * window))
        let edge = max(0, min(1, time / 0.18, (replay.duration - time) / 0.18))
        let weight = max(0, min(1, (speed - 0.04) / 0.10)) * edge
        return Pose(distance: traveled, gaitDistance: gaitDistance, strideScale: Self.strideScale(speed: speed), speed: speed, blend: weight * weight * (3 - 2 * weight))
    }
}
