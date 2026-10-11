import Foundation
import Testing
@testable import OrientationCore

private let origin = Date(timeIntervalSince1970: 1_000)
private func time(_ seconds: Double) -> Date { origin.addingTimeInterval(seconds) }
private func sample(_ seconds: Double, steps: Int, distance: Double? = nil) -> WalkingSample {
    WalkingSample(startDate: origin, endDate: time(seconds), steps: steps, distance: distance)
}
private func record(_ estimator: inout WalkingEstimator, id: UUID, from: Int, through: Int, degrees: Double) {
    for tick in from...through {
        estimator.recordHeading(degrees: degrees, at: time(Double(tick) / 10), cycleID: id)
    }
}

@Test("Cumulative reports contribute only the new steps and distance")
func cumulativeDeltas() throws {
    let id = UUID()
    var estimator = WalkingEstimator(cycleID: id, startedAt: origin)
    record(&estimator, id: id, from: 0, through: 20, degrees: 0)
    let firstResult = estimator.ingest(sample: sample(1, steps: 2), cycleID: id)
    let first = try #require(firstResult)
    let secondResult = estimator.ingest(sample: sample(2, steps: 4), cycleID: id)
    let second = try #require(secondResult)
    #expect(abs(first.estimatedDistance - 1.3) < 0.000_001)
    #expect(abs(second.estimatedDistance - 2.6) < 0.000_001)
    #expect(abs(second.forwardDisplacement - 2.6) < 0.000_001)
    #expect(abs(second.rightDisplacement) < 0.000_001)
    #expect(!second.isDisplacementUncertain)
}

@Test("A delayed report uses its heading interval rather than the current heading")
func delayedReportUsesHistory() throws {
    let id = UUID()
    var estimator = WalkingEstimator(cycleID: id, startedAt: origin, strideLength: 1)
    record(&estimator, id: id, from: 0, through: 10, degrees: 0)
    record(&estimator, id: id, from: 11, through: 30, degrees: 90)
    let reportResult = estimator.ingest(sample: sample(1, steps: 2), cycleID: id)
    let report = try #require(reportResult)
    #expect(abs(report.forwardDisplacement - 2) < 0.000_001)
    #expect(abs(report.rightDisplacement) < 0.000_001)
    #expect(!report.isDisplacementUncertain)
}

@Test("Directions on either side of 180 degrees average backward without a false full turn")
func circularAverageAtWrap() throws {
    let id = UUID()
    var estimator = WalkingEstimator(cycleID: id, startedAt: origin, strideLength: 1)
    record(&estimator, id: id, from: 0, through: 9, degrees: 179)
    record(&estimator, id: id, from: 10, through: 20, degrees: -179)
    let reportResult = estimator.ingest(sample: sample(2, steps: 2), cycleID: id)
    let report = try #require(reportResult)
    #expect(abs(report.forwardDisplacement + 2 * cos(.pi / 180)) < 0.000_001)
    #expect(abs(report.rightDisplacement) < 0.000_001)
    #expect(!report.isDisplacementUncertain)
}

@Test("An interval containing a turn keeps the mixed direction and marks uncertain")
func turningInterval() throws {
    let id = UUID()
    var estimator = WalkingEstimator(cycleID: id, startedAt: origin, strideLength: 1)
    record(&estimator, id: id, from: 0, through: 9, degrees: 0)
    record(&estimator, id: id, from: 10, through: 20, degrees: 90)
    let reportResult = estimator.ingest(sample: sample(2, steps: 2), cycleID: id)
    let report = try #require(reportResult)
    #expect(abs(report.forwardDisplacement - 1) < 0.000_001)
    #expect(abs(report.rightDisplacement - 1) < 0.000_001)
    #expect(report.isDisplacementUncertain)
}

@Test("A source chosen from stride does not jump when a system distance later appears")
func strideSourceDoesNotSwitch() throws {
    let id = UUID()
    var estimator = WalkingEstimator(cycleID: id, startedAt: origin)
    record(&estimator, id: id, from: 0, through: 20, degrees: 0)
    _ = estimator.ingest(sample: sample(1, steps: 2), cycleID: id)
    let reportResult = estimator.ingest(sample: sample(2, steps: 4, distance: 10), cycleID: id)
    let report = try #require(reportResult)
    #expect(report.source == .strideEstimate)
    #expect(abs(report.estimatedDistance - 2.6) < 0.000_001)
}

@Test("Missing system distances hold the baseline and later recovery counts distance once")
func systemSourceMissingDistance() throws {
    let id = UUID()
    var estimator = WalkingEstimator(cycleID: id, startedAt: origin)
    record(&estimator, id: id, from: 0, through: 30, degrees: 0)
    _ = estimator.ingest(sample: sample(1, steps: 2, distance: 1.4), cycleID: id)
    let missingResult = estimator.ingest(sample: sample(2, steps: 4), cycleID: id)
    let missing = try #require(missingResult)
    #expect(missing.steps == 4)
    #expect(missing.estimatedDistance == 1.4)
    #expect(missing.source == .systemEstimate)
    let recoveredResult = estimator.ingest(sample: sample(3, steps: 6, distance: 3.6), cycleID: id)
    let recovered = try #require(recoveredResult)
    #expect(abs(recovered.forwardDisplacement - 3.6) < 0.000_001)
    #expect(recovered.estimatedDistance == 3.6)
    #expect(recovered.isDisplacementUncertain)
}

@Test("Reset zeros the snapshot and prevents queued old callbacks contaminating the new cycle")
func resetAndStaleCycle() throws {
    let oldID = UUID()
    var estimator = WalkingEstimator(cycleID: oldID, startedAt: origin)
    record(&estimator, id: oldID, from: 0, through: 10, degrees: 30)
    _ = estimator.ingest(sample: sample(1, steps: 2), cycleID: oldID)
    let newID = UUID()
    let reset = estimator.reset(cycleID: newID, startedAt: time(2))
    #expect(reset == WalkSnapshot())
    let acceptedCondition1 = estimator.ingest(sample: sample(3, steps: 5), cycleID: oldID) == nil
    #expect(acceptedCondition1)
    let acceptedCondition2 = !estimator.recordHeading(degrees: 90, at: time(3), cycleID: oldID)
    #expect(acceptedCondition2)
    #expect(estimator.snapshot == WalkSnapshot())
    let fresh = WalkingSample(startDate: time(2), endDate: time(2.2), steps: 1, distance: nil)
    let freshResult = estimator.ingest(sample: fresh, cycleID: newID)
    #expect(try #require(freshResult).steps == 1)
}

@Test("Regressing, repeated and wrong-origin reports leave state unchanged")
func invalidReportsAreAtomic() throws {
    let id = UUID()
    var estimator = WalkingEstimator(cycleID: id, startedAt: origin)
    record(&estimator, id: id, from: 0, through: 20, degrees: 0)
    let baselineResult = estimator.ingest(sample: sample(1, steps: 4, distance: 3), cycleID: id)
    let baseline = try #require(baselineResult)
    let acceptedCondition3 = estimator.ingest(sample: sample(2, steps: 3, distance: 4), cycleID: id) == nil
    #expect(acceptedCondition3)
    let acceptedCondition5 = estimator.ingest(sample: sample(1, steps: 4, distance: 3), cycleID: id) == nil
    #expect(acceptedCondition5)
    let acceptedCondition6 = estimator.ingest(sample: WalkingSample(startDate: time(-1), endDate: time(2), steps: 5, distance: 4), cycleID: id) == nil
    #expect(acceptedCondition6)
    #expect(estimator.snapshot == baseline)
    let nextResult = estimator.ingest(sample: sample(2, steps: 5, distance: 4), cycleID: id)
    let next = try #require(nextResult)
    #expect(next.estimatedDistance == 4)
}

@Test("Out-of-order and nonfinite headings do not overwrite the current direction")
func invalidHeadings() throws {
    let id = UUID()
    var estimator = WalkingEstimator(cycleID: id, startedAt: origin, strideLength: 1)
    let acceptedCondition7 = estimator.recordHeading(degrees: 90, at: origin, cycleID: id)
    #expect(acceptedCondition7)
    let acceptedCondition8 = estimator.recordHeading(degrees: 90, at: time(0.2), cycleID: id)
    #expect(acceptedCondition8)
    let acceptedCondition9 = !estimator.recordHeading(degrees: 0, at: time(0.1), cycleID: id)
    #expect(acceptedCondition9)
    let acceptedCondition10 = !estimator.recordHeading(degrees: .nan, at: time(0.3), cycleID: id)
    #expect(acceptedCondition10)
    let reportResult = estimator.ingest(sample: sample(0.4, steps: 1), cycleID: id)
    let report = try #require(reportResult)
    #expect(abs(report.rightDisplacement - 1) < 0.000_001)
    #expect(abs(report.forwardDisplacement) < 0.000_001)
}

@Test("Missing heading coverage is marked uncertain")
func missingHeadingCoverage() throws {
    let id = UUID()
    var estimator = WalkingEstimator(cycleID: id, startedAt: origin)
    let reportResult = estimator.ingest(sample: sample(3, steps: 3), cycleID: id)
    let report = try #require(reportResult)
    #expect(report.isDisplacementUncertain)
}

@Test("Exhausted bounded history suppresses unobserved coordinates")
func historyBound() throws {
    let id = UUID()
    var estimator = WalkingEstimator(cycleID: id, startedAt: origin)
    record(&estimator, id: id, from: 0, through: 12_100, degrees: 90)
    let reportResult = estimator.ingest(sample: sample(1_210, steps: 100), cycleID: id)
    let report = try #require(reportResult)
    #expect(report.estimatedDistance == 65)
    #expect(report.forwardDisplacement == 0)
    #expect(report.rightDisplacement == 0)
    #expect(report.isDisplacementUncertain)
}

@Test("Completed logs preserve reset-cycle measurement and haptic evidence through JSON")
func sessionSerialization() throws {
    let record = SessionRecord(
        id: UUID(), startedAt: origin, endedAt: time(4), endReason: .reset,
        lastAngleDegrees: -30,
        hapticEvents: [HapticEventRecord(date: time(3), headingDegrees: -29, triggerAngleDegrees: -30, patternID: "left30")],
        walk: WalkSnapshot(steps: 7, estimatedDistance: 4.55, forwardDisplacement: 4.55, rightDisplacement: 0)
    )
    let data = try JSONEncoder().encode(record)
    #expect(try JSONDecoder().decode(SessionRecord.self, from: data) == record)
    #expect(record.duration == 4)
}

@Test("A corrected distance does not discard valid new steps")
func distanceCorrectionKeepsSteps() throws {
    let id = UUID()
    var estimator = WalkingEstimator(cycleID: id, startedAt: origin)
    _ = estimator.ingest(sample: sample(1, steps: 4, distance: 3), cycleID: id)
    let result = estimator.ingest(sample: sample(2, steps: 7, distance: 2), cycleID: id)
    let report = try #require(result)
    #expect(report.steps == 7)
    #expect(report.estimatedDistance == 3)
    #expect(report.isDisplacementUncertain)
}

@Test("Same-time corrected counts and unavailable distance still update steps")
func revisedCountAtSameTime() throws {
    let id = UUID()
    var estimator = WalkingEstimator(cycleID: id, startedAt: origin)
    _ = estimator.ingest(sample: sample(1, steps: 0, distance: 0), cycleID: id)
    let result = estimator.ingest(sample: sample(1, steps: 7, distance: .nan), cycleID: id)
    let report = try #require(result)
    #expect(report.steps == 7)
    #expect(report.source == .strideEstimate)
    #expect(report.isDisplacementUncertain)
}
