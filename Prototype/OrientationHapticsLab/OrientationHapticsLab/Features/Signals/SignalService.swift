import Combine
import Foundation

struct SignalPlaybackState: Equatable {
    var label: String?
    var angle: Double?
    var status: String
    var error: String?
}

@MainActor
protocol SignalOutput: AnyObject {
    var state: SignalPlaybackState { get }
    var statePublisher: AnyPublisher<SignalPlaybackState, Never> { get }
    func prepare()
    @discardableResult func playAngle(_ signedDegrees: Double, configuration: HapticConfiguration?) -> Bool
    @discardableResult func playReset() -> Bool
    func stop()
}

extension HapticService: SignalOutput {
    var state: SignalPlaybackState {
        .init(label: currentlyPlaying, angle: currentlyPlayingAngle, status: status, error: lastError)
    }

    var statePublisher: AnyPublisher<SignalPlaybackState, Never> {
        Publishers.CombineLatest4($currentlyPlaying, $currentlyPlayingAngle, $status, $lastError)
            .map { SignalPlaybackState(label: $0, angle: $1, status: $2, error: $3) }
            .eraseToAnyPublisher()
    }
}

/// Exactly one selected output receives commands; switching also cancels its active signal.
@MainActor
final class SignalService: ObservableObject {
    @Published private(set) var mode: SignalMode
    @Published private(set) var state: SignalPlaybackState
    private let outputs: [SignalMode: any SignalOutput]
    private var subscription: AnyCancellable?
    private var output: any SignalOutput { outputs[mode]! }

    convenience init(mode: SignalMode = .haptic) {
        self.init(mode: mode, outputs: [
            .haptic: HapticService(),
            .speech: AudioSignalService(mode: .speech),
            .beep: AudioSignalService(mode: .beep)
        ])
    }

    init(mode: SignalMode, outputs: [SignalMode: any SignalOutput]) {
        precondition(SignalMode.allCases.allSatisfy { outputs[$0] != nil })
        self.outputs = outputs
        self.mode = mode
        state = outputs[mode]!.state
        observeSelectedOutput()
    }

    func setMode(_ newMode: SignalMode) {
        guard newMode != mode else { return }
        subscription = nil
        output.stop()
        mode = newMode
        observeSelectedOutput()
        prepare()
    }

    func prepare() { output.prepare() }
    func stop() { output.stop() }

    @discardableResult
    func playAngle(_ signedDegrees: Double, configuration: HapticConfiguration? = nil) -> Bool {
        output.playAngle(signedDegrees, configuration: configuration)
    }

    @discardableResult
    func playReset() -> Bool { output.playReset() }

    func description(for angle: Int, configuration: HapticConfiguration) -> String {
        switch mode {
        case .haptic: configuration.describe
        case .speech: AudioCue.angle(Double(angle))?.speech ?? "지원하지 않는 각도"
        case .beep: AudioCue.angle(Double(angle))?.beepDescription ?? "지원하지 않는 각도"
        }
    }

    private func observeSelectedOutput() {
        state = output.state
        subscription = output.statePublisher.sink { [weak self] state in self?.state = state }
    }
}
