import CoreHaptics
import SwiftUI

enum PlaybackError: LocalizedError {
    case unsupported, busy, interrupted, cancelled, engine(String)
    var errorDescription: String? {
        switch self {
        case .unsupported: return "이 기기는 햅틱을 지원하지 않습니다. 실제 iPhone에서 실행해 주세요."
        case .busy: return "현재 진동이 끝난 뒤 다시 재생해 주세요."
        case .interrupted: return "앱 상태가 바뀌어 재생이 중단되었습니다. 다시 재생해 주세요."
        case .cancelled: return "재생을 중지했습니다."
        case .engine(let message): return "햅틱 재생 실패: \(message)"
        }
    }
}

@MainActor
final class HapticService: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published var error: String?
    let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    let isPreview: Bool
    var canPlay: Bool { supportsHaptics || isPreview }
    private let hardware = HapticHardware()
    private var completion: CheckedContinuation<Void, Error>?
    private var startTimeout: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var token: UUID?
    private var playbackAcknowledged = false
    private var scheduleElapsed = false
    #if DEBUG
    private var injectedFailure = false
    #endif

    init() {
        #if DEBUG && targetEnvironment(simulator)
        isPreview = ProcessInfo.processInfo.arguments.contains("--ui-preview")
        #else
        isPreview = false
        #endif
    }
    func play(_ pattern: HapticPattern, gain: Double = 1) async throws {
        guard canPlay else { throw PlaybackError.unsupported }
        guard !isPlaying else { throw PlaybackError.busy }
        try Task.checkCancellation()
        let compiled = try PatternCompiler.compile(pattern, gain: gain)
        let request = UUID()
        token = request; isPlaying = true
        playbackAcknowledged = false; scheduleElapsed = false
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                completion = continuation
                // Arm this BEFORE any hardware work. A stalled engine must not freeze the UI
                // or leave the caller's continuation waiting forever.
                startTimeout = Task {
                    do { try await Task.sleep(for: .seconds(4)) } catch { return }
                    finish(request, error: PlaybackError.engine("진동 시작 응답이 없습니다. 다시 시작해 주세요."))
                }
                #if DEBUG
                let args = ProcessInfo.processInfo.arguments
                if !injectedFailure && args.contains("--ui-testing") && args.contains("--haptic-start-stall") {
                    injectedFailure = true
                    return
                }
                if !injectedFailure && args.contains("--ui-testing") && args.contains("--haptic-completion-stall") {
                    injectedFailure = true
                    didStart(request, duration: compiled.duration)
                    return
                }
                #endif
                if isPreview {
                    playbackAcknowledged = true
                    didStart(request, duration: compiled.duration)
                } else {
                    hardware.play(compiled, token: request, started: { [weak self] in
                        Task { @MainActor in self?.didStart(request, duration: compiled.duration) }
                    }, completed: { [weak self] result in
                        Task { @MainActor in
                            guard let self, self.token == request else { return }
                            if let result { self.finish(request, error: result) }
                            else {
                                self.playbackAcknowledged = true
                                if self.scheduleElapsed { self.finish(request, error: nil) }
                            }
                        }
                    })
                }
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in self?.finish(request, error: PlaybackError.cancelled) }
        })
    }
    private func didStart(_ request: UUID, duration: Double) {
        guard token == request else { return }
        startTimeout?.cancel(); startTimeout = nil
        finishTask = Task {
            do { try await Task.sleep(for: .seconds(duration + 0.05)) } catch { return }
            guard token == request else { return }
            scheduleElapsed = true
            if playbackAcknowledged { finish(request, error: nil); return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            finish(request, error: PlaybackError.engine("진동 완료 응답이 없습니다. 다시 시작해 주세요."))
        }
    }
    private func finish(_ expectedToken: UUID, error: Error?) {
        guard token == expectedToken else { return }
        token = nil; isPlaying = false
        startTimeout?.cancel(); startTimeout = nil
        finishTask?.cancel(); finishTask = nil
        hardware.finish(expectedToken, cancel: error != nil)
        let callback = completion; completion = nil
        if let error { callback?.resume(throwing: error) } else { callback?.resume() }
    }
    func stop(interrupted: Bool = false) {
        if let token { finish(token, error: interrupted ? PlaybackError.interrupted : PlaybackError.cancelled) }
    }
    func preview(_ pattern: HapticPattern, gain: Double = 1) {
        guard !isPlaying else { return }
        Task {
            do { try await play(pattern, gain: gain) }
            catch { self.error = error.localizedDescription }
        }
    }
}
