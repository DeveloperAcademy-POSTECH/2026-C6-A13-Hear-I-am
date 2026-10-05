import SwiftUI

@MainActor
final class RandomPracticeRunner: ObservableObject {
    enum Phase { case ready, preparing, countdown, playing, orienting, feedback, interrupted }
    struct Feedback {
        let expected: Direction
        let answer: RotationAnswer
        var isCorrect: Bool { answer.isCorrect(for: expected) }
    }
    let set: PatternSet
    let preferences: AppPreferences
    @Published private(set) var phase: Phase = .ready
    @Published private(set) var countdown = 3
    @Published private(set) var completed = 0
    @Published private(set) var relativeDegrees = 0
    @Published private(set) var faceUp = true
    @Published private(set) var feedback: Feedback?
    @Published private(set) var issue: String?
    let isPreview: Bool
    private var hiddenDirection: Direction?
    private var source = RandomDirectionSource(seed: UInt64.random(in: 0...UInt64.max))
    private let haptics: HapticService
    private let motion: RotationMotionService
    private let sound = FeedbackSoundService()
    private var hold: RotationHold?
    private var referenceYaw: Double?
    private var answerBeganAt = 0.0
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(set: PatternSet, preferences: AppPreferences, haptics: HapticService) {
        self.set = set; self.preferences = preferences.validated; self.haptics = haptics
        isPreview = haptics.isPreview
        motion = RotationMotionService(isPreview: haptics.isPreview)
    }
    func start() {
        guard phase == .ready || phase == .feedback || phase == .interrupted else { return }
        if phase != .interrupted || hiddenDirection == nil { hiddenDirection = nextDirection() }
        guard let direction = hiddenDirection else { return }
        task?.cancel()
        let current = UUID(); generation = current
        issue = nil; feedback = nil; referenceYaw = nil; hold = nil
        relativeDegrees = 0; faceUp = true
        do {
            if preferences.successSound && !isPreview { try sound.prepare() }
            try motion.start(onSample: { [weak self] in self?.receive($0) },
                             onFailure: { [weak self] in self?.interrupt(message: $0.localizedDescription) })
        } catch { interrupt(message: error.localizedDescription, force: true); return }
        phase = .preparing; countdown = preferences.preparationSeconds
        task = Task {
            do {
                _ = try await motion.waitForReference()
                try Task.checkCancellation()
                guard generation == current else { return }
                phase = .countdown
                for remaining in (1...preferences.preparationSeconds).reversed() {
                    countdown = remaining
                    try await Task.sleep(for: .seconds(1))
                }
                try Task.checkCancellation()
                guard generation == current else { return }
                // One reference per round. Replays keep it; the next round takes a new one.
                if (try? motion.reference()) == nil { phase = .preparing }
                referenceYaw = try await motion.waitForReference()
                while !Task.isCancelled && generation == current {
                    phase = .playing; hold = nil
                    try await haptics.play(set.pattern(for: direction), gain: preferences.gain)
                    try Task.checkCancellation()
                    guard generation == current else { return }
                    hold = RotationHold()
                    // Compare sensor timestamps only with another sensor timestamp.
                    answerBeganAt = motion.latest?.time ?? 0
                    phase = .orienting
                    // Hands-free replay if the person needs more time to recognize the cue.
                    try await Task.sleep(for: .seconds(10))
                }
            } catch {
                guard generation == current else { return }
                interrupt(message: error.localizedDescription)
            }
        }
    }
    private func receive(_ sample: RotationMotionService.Sample) {
        if faceUp != sample.faceUp { faceUp = sample.faceUp }
        guard let referenceYaw else { return }
        let degrees = RotationRecognition.clockwiseDegrees(yaw: sample.yaw, referenceYaw: referenceYaw)
        guard degrees.isFinite else { return }
        let rounded = Int(degrees.rounded())
        if rounded != relativeDegrees { relativeDegrees = rounded }
        guard phase == .orienting, sample.time - answerBeganAt >= 0.5 else { return }
        if let answer = hold?.update(degrees: degrees, angularSpeed: sample.angularSpeed, faceUp: sample.faceUp, time: sample.time) {
            submit(answer)
        }
    }
    private func submit(_ answer: RotationAnswer) {
        guard phase == .orienting, let direction = hiddenDirection else { return }
        generation = UUID(); task?.cancel()
        let result = Feedback(expected: direction, answer: answer)
        feedback = result; phase = .feedback; completed += 1
        do { if preferences.successSound && !isPreview { try sound.play(correct: result.isCorrect) } }
        catch { interrupt(message: error.localizedDescription); return }
        let current = generation
        task = Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard generation == current, phase == .feedback else { return }
            start()
        }
    }
    func interrupt(message: String = "잠시 멈췄어요. 다시 시작하면 지금 방향을 기준으로 준비합니다.", force: Bool = false) {
        guard force || (phase != .ready && phase != .interrupted) else { return }
        if phase == .feedback { hiddenDirection = nil }
        generation = UUID(); task?.cancel(); haptics.stop(interrupted: true)
        motion.stop(); sound.close(); hold = nil; referenceYaw = nil
        issue = message; phase = .interrupted
    }
    func close() {
        generation = UUID(); task?.cancel(); haptics.stop()
        motion.stop(); sound.close(); hold = nil; referenceYaw = nil
    }
    private func nextDirection() -> Direction {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--hardware-test-front") {
            return .front
        }
        #endif
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-testing") && args.contains("--rotation-test-sequence") {
            return [.right, .back, .front, .left][completed % 4]
        }
        #endif
        return source.next()
    }
    #if DEBUG && targetEnvironment(simulator)
    func rotatePreview(by degrees: Double) { motion.rotatePreview(by: degrees) }
    #endif
}
