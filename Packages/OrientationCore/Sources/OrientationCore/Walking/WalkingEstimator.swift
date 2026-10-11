import Foundation

public enum WalkDistanceSource: String, Codable, Sendable {
    case systemEstimate
    case strideEstimate
}

/// Coordinates assume forward steps in the direction of the phone. They are not measured positions.
public struct WalkSnapshot: Codable, Equatable, Sendable {
    public var steps: Int
    public var estimatedDistance: Double
    public var forwardDisplacement: Double
    public var rightDisplacement: Double
    public var source: WalkDistanceSource
    public var isDisplacementUncertain: Bool

    public init(
        steps: Int = 0,
        estimatedDistance: Double = 0,
        forwardDisplacement: Double = 0,
        rightDisplacement: Double = 0,
        source: WalkDistanceSource = .strideEstimate,
        isDisplacementUncertain: Bool = false
    ) {
        self.steps = steps
        self.estimatedDistance = estimatedDistance
        self.forwardDisplacement = forwardDisplacement
        self.rightDisplacement = rightDisplacement
        self.source = source
        self.isDisplacementUncertain = isDisplacementUncertain
    }
}

/// A cumulative pedometer report whose origin is the current cycle's reset time.
public struct WalkingSample: Sendable {
    public let startDate: Date
    public let endDate: Date
    public let steps: Int
    public let distance: Double?

    public init(startDate: Date, endDate: Date, steps: Int, distance: Double?) {
        self.startDate = startDate
        self.endDate = endDate
        self.steps = steps
        self.distance = distance
    }
}

/// Consumes cumulative reports and relative headings. All distances are in meters; clockwise is positive.
/// Each distance delta is spread uniformly across its report interval. Without per-step timestamps,
/// turns cannot be resolved exactly, so turning intervals remain explicitly uncertain.
public struct WalkingEstimator: Sendable {
    public private(set) var cycleID: UUID
    public private(set) var startedAt: Date
    public private(set) var snapshot = WalkSnapshot()
    public let strideLength: Double

    private struct Heading: Sendable {
        var date: Date
        var degrees: Double
    }

    private var headings: [Heading] = []
    private var selectedSource: WalkDistanceSource?
    private var lastReportEnd: Date?
    private var lastDistanceEnd: Date
    private var lastCumulativeDistance: Double = 0
    private let maximumHeadingGap: TimeInterval = 0.6
    private let maximumHistoryCount = 12_000

    public init(cycleID: UUID, startedAt: Date, strideLength: Double = 0.65) {
        self.cycleID = cycleID
        self.startedAt = startedAt
        self.lastDistanceEnd = startedAt
        self.strideLength = strideLength.isFinite && strideLength > 0 ? strideLength : 0.65
        self.headings = [Heading(date: startedAt, degrees: 0)]
    }

    @discardableResult
    public mutating func reset(cycleID: UUID, startedAt: Date) -> WalkSnapshot {
        self = WalkingEstimator(cycleID: cycleID, startedAt: startedAt, strideLength: strideLength)
        return snapshot
    }

    /// Drops old-cycle, nonfinite and out-of-order samples. Same-time samples replace the last heading.
    @discardableResult
    public mutating func recordHeading(degrees: Double, at date: Date, cycleID: UUID) -> Bool {
        guard cycleID == self.cycleID, degrees.isFinite, date.timeIntervalSinceReferenceDate.isFinite,
              date >= startedAt, date >= (headings.last?.date ?? startedAt) else { return false }
        let heading = Heading(date: date, degrees: Self.normalized(degrees))
        if headings.last?.date == date {
            headings[headings.count - 1] = heading
        } else {
            headings.append(heading)
        }
        if headings.count > maximumHistoryCount {
            headings.removeFirst(headings.count - maximumHistoryCount)
            // If reports are unavailable for a long time, retained history may no longer cover the interval.
            snapshot.isDisplacementUncertain = true
        }
        return true
    }

    /// Returns nil for wrong-cycle, stale, malformed or regressing cumulative reports.
    /// Pass the cycle's exact requested start time as sample.startDate, not a new callback receipt time.
    @discardableResult
    public mutating func ingest(sample: WalkingSample, cycleID: UUID) -> WalkSnapshot? {
        guard cycleID == self.cycleID, sample.startDate == startedAt,
              sample.endDate.timeIntervalSinceReferenceDate.isFinite,
              sample.endDate > startedAt, sample.endDate >= (lastReportEnd ?? startedAt),
              sample.steps >= snapshot.steps else { return nil }
        // Step counts stay useful even when an optional distance estimate is missing or corrected.
        let validDistance = sample.distance.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let hasMovement = sample.steps > 0 || (validDistance ?? 0) > 0
        let source = selectedSource ?? (validDistance != nil ? .systemEstimate : .strideEstimate)
        let cumulativeDistance: Double?
        switch source {
        case .systemEstimate:
            cumulativeDistance = validDistance.flatMap { $0 >= lastCumulativeDistance ? $0 : nil }
        case .strideEstimate:
            cumulativeDistance = Double(sample.steps) * strideLength
        }
        if let lastReportEnd, sample.endDate == lastReportEnd,
           sample.steps == snapshot.steps, (cumulativeDistance ?? lastCumulativeDistance) == lastCumulativeDistance { return nil }
        if sample.distance != nil && (validDistance == nil || cumulativeDistance == nil) {
            snapshot.isDisplacementUncertain = true
        }
        if selectedSource == nil && hasMovement {
            selectedSource = source
        }
        snapshot.steps = sample.steps
        snapshot.source = selectedSource ?? .strideEstimate
        lastReportEnd = sample.endDate

        guard let cumulativeDistance else {
            // Keep the prior distance endpoint so a later estimate covers the whole missing interval once.
            snapshot.isDisplacementUncertain = true
            return snapshot
        }
        let delta = cumulativeDistance - lastCumulativeDistance
        if delta > 0 {
            let direction = averageDirection(from: lastDistanceEnd, to: sample.endDate)
            snapshot.forwardDisplacement += delta * direction.forward
            snapshot.rightDisplacement += delta * direction.right
            snapshot.isDisplacementUncertain = snapshot.isDisplacementUncertain || direction.uncertain
        }
        snapshot.estimatedDistance = cumulativeDistance
        lastCumulativeDistance = cumulativeDistance
        lastDistanceEnd = sample.endDate
        pruneHeadings(through: sample.endDate)
        return snapshot
    }

    private mutating func pruneHeadings(through date: Date) {
        // Preserve one heading at/before the endpoint to anchor the next report, plus newer headings.
        if let anchorIndex = headings.lastIndex(where: { $0.date <= date }), anchorIndex > 0 {
            headings.removeFirst(anchorIndex)
        }
    }

    private func averageDirection(from start: Date, to end: Date) -> (forward: Double, right: Double, uncertain: Bool) {
        let duration = end.timeIntervalSince(start)
        guard duration > 0, let first = headings.first else { return (0, 0, true) }
        // History exhausted: avoid projecting an unobserved interval using a recent direction.
        guard first.date <= start else { return (0, 0, true) }
        var current = headings.last(where: { $0.date <= start }) ?? first
        var cursor = start
        var forward: Double = 0
        var right: Double = 0
        var uncertain = false
        var unwrapped = current.degrees
        var minimum = unwrapped
        var maximum = unwrapped

        for next in headings where next.date > start && next.date <= end {
            let span = next.date.timeIntervalSince(cursor)
            let radians = current.degrees * .pi / 180
            forward += cos(radians) * span
            right += sin(radians) * span
            if next.date.timeIntervalSince(current.date) > maximumHeadingGap { uncertain = true }
            unwrapped += Self.normalized(next.degrees - current.degrees)
            minimum = min(minimum, unwrapped)
            maximum = max(maximum, unwrapped)
            current = next
            cursor = next.date
        }
        let tail = end.timeIntervalSince(cursor)
        forward += cos(current.degrees * .pi / 180) * tail
        right += sin(current.degrees * .pi / 180) * tail
        if end.timeIntervalSince(current.date) > maximumHeadingGap { uncertain = true }
        return (forward / duration, right / duration, uncertain || maximum - minimum > 15)
    }

    private static func normalized(_ angle: Double) -> Double {
        let remainder = angle.truncatingRemainder(dividingBy: 360)
        if remainder > 180 { return remainder - 360 }
        if remainder < -180 { return remainder + 360 }
        return remainder
    }
}
