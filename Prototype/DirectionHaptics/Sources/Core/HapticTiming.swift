import Foundation

extension HapticStep {
    /// A transient's duration cannot be stretched by Core Haptics; use a continuous event.
    public mutating func setLength(_ seconds: Double) {
        guard seconds.isFinite else { return }
        if kind == .tap { kind = .continuous; envelope = .flat }
        duration = min(2, max(0.03, seconds))
    }
}

extension HapticPattern {
    /// The range in which all timing ratios fit the block, repeat-gap, and total limits.
    public var adjustableDurationRange: ClosedRange<Double>? {
        guard (1...16).contains(steps.count), steps.contains(where: { $0.kind != .pause }),
              (1...5).contains(repetitions), repeatGap.isFinite, (0.1...2).contains(repeatGap),
              duration.isFinite, duration > 0 else { return nil }
        var minimumScale = 0.0
        var maximumScale = Double.infinity
        for step in steps {
            let length = step.scheduledDuration
            guard length.isFinite, (0.03...2).contains(length) else { return nil }
            minimumScale = max(minimumScale, 0.03 / length)
            maximumScale = min(maximumScale, 2 / length)
        }
        if repetitions > 1 {
            minimumScale = max(minimumScale, 0.1 / repeatGap)
            maximumScale = min(maximumScale, 2 / repeatGap)
        }
        let lower = duration * minimumScale
        let upper = min(12, duration * maximumScale)
        guard lower <= upper else { return nil }
        return lower...upper
    }

    /// Resize this direction only, preserving rhythm, envelopes, intensity, and block IDs.
    public func resized(to requestedDuration: Double) -> Self {
        guard requestedDuration.isFinite, let range = adjustableDurationRange else { return self }
        let target = min(range.upperBound, max(range.lowerBound, requestedDuration))
        guard abs(target - duration) > 0.000_000_001 else { return self }
        // Leave a sub-nanosecond margin so floating-point sums cannot exceed 12 seconds.
        let scale = min(target, 12 - 0.000_000_001) / duration
        var result = self
        for index in steps.indices {
            result.steps[index].setLength(steps[index].scheduledDuration * scale)
        }
        if repetitions > 1 { result.repeatGap = min(2, max(0.1, repeatGap * scale)) }
        return result
    }
}
