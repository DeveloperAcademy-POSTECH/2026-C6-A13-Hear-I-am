import SwiftUI

@MainActor
final class StudyRunner: ObservableObject {
    enum Phase { case practice, practicing, ready, countdown, playing, answer, rating, finished, interrupted }
    @Published private(set) var session: StudySession
    @Published private(set) var phase: Phase = .practice
    @Published private(set) var block = 0
    @Published private(set) var trial = 0
    @Published private(set) var practiceCounts: [Direction: Int] = [:]
    @Published private(set) var replayCount = 0
    @Published private(set) var countdown = 3
    @Published private(set) var issue: String?
    private let haptics: HapticService
    private let preparationSeconds: Int
    private var operation: Task<Void, Never>?
    private var generation = UUID()
    private var endedUptime: TimeInterval?

    init(session: StudySession, haptics: HapticService, preparationSeconds: Int = 3) {
        self.session = session; self.haptics = haptics
        self.preparationSeconds = min(10, max(1, preparationSeconds))
    }
    var set: PatternSet { session.sets[block] }
    var expected: Direction { session.orders[block][trial] }
    var blockCount: Int { session.orders[block].count }
    var practiceComplete: Bool { Direction.allCases.allSatisfy { practiceCounts[$0, default: 0] >= 2 } }
    var progress: Double {
        let completed = session.orders.prefix(block).reduce(0) { $0 + $1.count } + trial
        return Double(completed) / Double(max(1, session.plannedCount))
    }

    func practice(_ direction: Direction) {
        guard phase == .practice, practiceCounts[direction, default: 0] < 2 else { return }
        let id = UUID(); generation = id; phase = .practicing; issue = nil
        operation = Task {
            do {
                try await haptics.play(set.pattern(for: direction), gain: session.context.gain)
                guard generation == id else { return }
                practiceCounts[direction, default: 0] += 1; phase = .practice
            } catch {
                guard generation == id else { return }
                issue = error.localizedDescription; phase = .practice
            }
        }
    }
    func beginTrials() { if phase == .practice && practiceComplete { phase = .ready; issue = nil } }

    func playTrial(replay: Bool = false) {
        guard (replay && phase == .answer) || (!replay && (phase == .ready || phase == .interrupted)) else { return }
        let id = UUID(); generation = id; issue = nil; endedUptime = nil; countdown = preparationSeconds; phase = .countdown
        operation = Task {
            do {
                for value in (1...preparationSeconds).reversed() {
                    countdown = value
                    try await Task.sleep(for: .seconds(1))
                }
                try Task.checkCancellation()
                guard generation == id else { return }
                phase = .playing
                try await haptics.play(set.pattern(for: expected), gain: session.context.gain)
                guard generation == id else { return }
                if replay { replayCount += 1 }
                endedUptime = ProcessInfo.processInfo.systemUptime
                phase = .answer
            } catch {
                guard generation == id else { return }
                recordFailure(error.localizedDescription)
            }
        }
    }
    func answer(_ direction: Direction?) {
        guard phase == .answer else { return }
        let elapsed = endedUptime.map { max(0, (ProcessInfo.processInfo.systemUptime - $0) * 1000) }
        session.records.append(.init(block: block, index: trial, expected: expected, answered: direction,
                                     outcome: .answered, replays: replayCount, responseMilliseconds: elapsed))
        advance()
    }
    func skip() {
        guard phase == .interrupted else { return }
        session.records.append(.init(block: block, index: trial, expected: expected, outcome: .skipped, note: "재생 실패 후 건너뜀"))
        advance()
    }
    private func advance() {
        replayCount = 0; endedUptime = nil; issue = nil
        if trial + 1 < blockCount { trial += 1; phase = .ready } else { phase = .rating }
    }
    func rate(comfort: Int, confidence: Int, effort: Int, note: String) {
        guard phase == .rating else { return }
        session.ratings.append(.init(block: block, comfort: comfort, confidence: confidence, effort: effort, note: note))
        let isLast = block + 1 == session.sets.count
        if isLast { session.status = .completed; session.endedAt = Date() }
        if isLast { phase = .finished }
        else { block += 1; trial = 0; practiceCounts = [:]; phase = .practice }
    }
    private func recordFailure(_ message: String) {
        issue = message
        session.records.append(.init(block: block, index: trial, expected: expected, outcome: .failed,
                                     replays: replayCount, note: message))
        replayCount = 0; endedUptime = nil
        phase = .interrupted
    }
    func pause() {
        guard phase == .countdown || phase == .playing || phase == .answer || phase == .practicing else { return }
        let wasPractice = phase == .practicing
        generation = UUID(); operation?.cancel(); haptics.stop(interrupted: true)
        if wasPractice { issue = "학습 재생이 중단됐어요. 다시 느껴보세요."; phase = .practice }
        else { recordFailure("화면 전환 또는 사용자 중지로 시행이 중단됨") }
    }
    func stopSession() {
        generation = UUID(); operation?.cancel(); haptics.stop()
        session.status = .stopped; session.endedAt = Date()
        phase = .finished
    }
}
