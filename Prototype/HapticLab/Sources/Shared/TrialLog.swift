import Foundation

/// 실험 한 판의 기록. 문서 §C "공통 기록"에 맞춘다.
/// 평균만으로 판단하지 않기 위해 원자료를 그대로 남긴다.
struct Trial: Codable, Identifiable, Sendable {
    var id = UUID()
    var experiment: String       // E1 / E6-1 / E6-2 / E8 …
    var at: Date = Date()
    var condition: String        // 제시한 조건
    var expected: String         // 정답
    var answered: String         // 응답
    var reactionMs: Double       // 제시부터 응답까지
    var note: String = ""

    var isCorrect: Bool { expected == answered }
}

/// 기록을 모으고 TSV 로 뽑는다. 표 파일은 커밋하지 않는다.
/// 기기 안에 저장한다 — 앱을 껐다 켜도 남아야 결과를 옮겨 적을 수 있다.
@MainActor
final class TrialStore: ObservableObject {
    @Published private(set) var trials: [Trial] = [] {
        didSet { save() }
    }

    private static let key = "trials.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Trial].self, from: data) {
            trials = saved
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(trials) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func add(_ trial: Trial) { trials.append(trial) }
    func clear() { trials.removeAll() }

    func trials(of experiment: String) -> [Trial] {
        trials.filter { $0.experiment == experiment }
    }

    func accuracy(of experiment: String) -> Double? {
        let rows = trials(of: experiment)
        guard !rows.isEmpty else { return nil }
        return Double(rows.filter(\.isCorrect).count) / Double(rows.count)
    }

    /// 문서 §C — 평균만 쓰지 말고 95백분위와 최대값을 같이 남긴다.
    nonisolated static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = p * Double(sorted.count - 1)
        let low = Int(rank.rounded(.down)), high = Int(rank.rounded(.up))
        if low == high { return sorted[low] }
        let weight = rank - Double(low)
        return sorted[low] * (1 - weight) + sorted[high] * weight
    }

    /// 쉼표는 쓰지 않는다 — 설명에 쉼표가 들어가면 표가 깨진다.
    var tsv: String {
        var out = "experiment\tat\tcondition\texpected\tanswered\tcorrect\treaction_ms\tnote\n"
        let fmt = ISO8601DateFormatter()
        for t in trials {
            let cells = [
                t.experiment, fmt.string(from: t.at), t.condition, t.expected,
                t.answered, t.isCorrect ? "1" : "0",
                String(format: "%.1f", t.reactionMs), t.note
            ].map { $0.replacingOccurrences(of: "\t", with: " ") }
            out += cells.joined(separator: "\t") + "\n"
        }
        return out
    }
}
