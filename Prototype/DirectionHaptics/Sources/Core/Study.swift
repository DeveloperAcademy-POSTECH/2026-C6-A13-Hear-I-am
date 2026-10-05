import Foundation

public enum InputMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case participant, facilitator
    public var id: String { rawValue }
    public var title: String { self == .participant ? "참여자 직접 입력" : "진행자 대신 기록" }
}

public struct StudyContext: Codable, Equatable, Sendable {
    public var placement = "손에 쥠"
    public var activity = "정지"
    public var inputMode: InputMode = .facilitator
    public var gain = 1.0
    public var device = ""
    public var os = ""
    public var isPreview = false
    public init() {}
}

public enum TrialOutcome: String, Codable, Sendable { case answered, failed, skipped }
public struct TrialRecord: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var block: Int
    public var index: Int
    public var expected: Direction
    public var answered: Direction?
    public var outcome: TrialOutcome
    public var replays: Int
    public var responseMilliseconds: Double?
    public var note: String
    public init(block: Int, index: Int, expected: Direction, answered: Direction? = nil,
                outcome: TrialOutcome, replays: Int = 0, responseMilliseconds: Double? = nil, note: String = "") {
        self.block = block; self.index = index; self.expected = expected; self.answered = answered
        self.outcome = outcome; self.replays = replays; self.responseMilliseconds = responseMilliseconds; self.note = note
    }
    public var isCorrect: Bool { outcome == .answered && answered == expected }
}

public struct BlockRating: Codable, Equatable, Sendable {
    public var block: Int
    public var comfort: Int
    public var confidence: Int
    public var effort: Int
    public var note: String
    public init(block: Int, comfort: Int, confidence: Int, effort: Int, note: String = "") {
        self.block = block; self.comfort = comfort; self.confidence = confidence; self.effort = effort; self.note = note
    }
}

public enum SessionStatus: String, Codable, Sendable { case inProgress, completed, stopped }
public struct StudySession: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var startedAt = Date()
    public var endedAt: Date?
    public var status: SessionStatus = .inProgress
    public var context: StudyContext
    public var seed: UInt64
    public var repetitions: Int
    /// Complete, immutable copies in actual presentation order.
    public var sets: [PatternSet]
    public var orders: [[Direction]]
    public var records: [TrialRecord] = []
    public var ratings: [BlockRating] = []

    public init(sets: [PatternSet], context: StudyContext, repetitions: Int = 5, seed: UInt64) {
        self.context = context; self.repetitions = repetitions; self.seed = seed
        var generator = SeededGenerator(seed: seed)
        self.sets = sets.shuffled(using: &generator)
        self.orders = sets.map { _ in
            Array(repeating: Direction.allCases, count: max(1, repetitions)).flatMap { $0 }.shuffled(using: &generator)
        }
    }
    public var plannedCount: Int { orders.reduce(0) { $0 + $1.count } }
    public var answeredCount: Int { records.filter { $0.outcome == .answered }.count }
    public func statistics(block: Int) -> StudyStatistics { .init(records: records.filter { $0.block == block }) }
}

/// SplitMix64; stored seeds reproduce both block order and direction order.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

public struct StudyStatistics: Sendable {
    public let records: [TrialRecord]
    public init(records: [TrialRecord]) { self.records = records }
    public var scored: [TrialRecord] { records.filter { $0.outcome == .answered } }
    public var correct: Int { scored.filter(\.isCorrect).count }
    public var accuracy: Double? { scored.isEmpty ? nil : Double(correct) / Double(scored.count) }
    /// First-play success uses all answered trials as the denominator, including replayed trials.
    public var firstPlayAccuracy: Double? {
        scored.isEmpty ? nil : Double(scored.filter { $0.isCorrect && $0.replays == 0 }.count) / Double(scored.count)
    }
    public var replays: Int { scored.reduce(0) { $0 + $1.replays } }
    public var failures: Int { records.filter { $0.outcome == .failed }.count }
    public var skipped: Int { records.filter { $0.outcome == .skipped }.count }
    public func accuracy(for direction: Direction) -> Double? {
        let subset = scored.filter { $0.expected == direction }
        return subset.isEmpty ? nil : Double(subset.filter(\.isCorrect).count) / Double(subset.count)
    }
    public func confusion(expected: Direction, answered: Direction?) -> Int {
        scored.filter { $0.expected == expected && $0.answered == answered }.count
    }
}

public enum PairPreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case a, b, equal, unsure
    public var id: String { rawValue }
    public var title: String {
        switch self { case .a: return "A가 더 또렷해요"; case .b: return "B가 더 또렷해요"; case .equal: return "비슷해요"; case .unsure: return "잘 모르겠어요" }
    }
}

/// Only reusable pattern settings are persisted. Experiment responses stay in memory.
public struct AppArchive: Codable, Sendable {
    public var schemaVersion = 1
    public var userSets: [PatternSet] = []
    public var favorites: Set<UUID> = []
    public init() {}
}
