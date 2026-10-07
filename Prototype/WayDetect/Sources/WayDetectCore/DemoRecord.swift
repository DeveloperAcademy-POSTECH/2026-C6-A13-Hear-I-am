import Foundation

public enum DemoRecord {
    /// Synthetic chart fixture, never represented as a device measurement.
    public static func make() -> SessionRecord {
        var record = SessionRecord(startedAt: Date().addingTimeInterval(-60), endedAt: Date(),
                                   route: .example, settings: .init(), isDemo: true, outcome: "그래프 예시")
        for i in 0...600 {
            let t = Double(i) / 10, spot = min(2, Int(t / 20)), local = t.truncatingRemainder(dividingBy: 20)
            let steps = min(10, Int(local / 1.5))
            let target = Angles.clockOffset(record.route.spots[spot].clock)
            let error = sin(t * 0.45) * (spot == 1 ? 35 : 8)
            record.samples.append(TraceSample(time: t, spot: spot, revision: spot + 1, phase: .walking,
                relativeHeading: target - error, targetHeading: target, error: error, steps: steps, stepGoal: 10,
                estimatedTotal: spot * 10 + steps, systemTotal: max(0, spot * 10 + steps - 3),
                verticalAcceleration: sin(t * 8) * 0.15, sensorAge: 0.02, sensorValid: true))
        }
        record.estimatedTotal = 30; record.systemTotal = 28; record.confirmedSpots = 3
        record.events = [RunEvent(time: 0, spot: 0, kind: "12시 설정", message: "출발 정면 설정 · 예시"),
                         RunEvent(time: 20, spot: 1, kind: "12시 설정", message: "첫 스팟 도착 · 새 12시 설정 · 예시"),
                         RunEvent(time: 40, spot: 2, kind: "12시 설정", message: "두 번째 스팟 도착 · 새 12시 설정 · 예시")]
        return record
    }
}
