import CoreHaptics
import Foundation

/// Core Haptics may wait on the haptic server. Keep every native call off the UI actor.
/// Engine/player state belongs exclusively to queue; the request fence is lock protected
/// so cancellation remains immediate even while a native call is stalled.
final class HapticHardware: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.heariam.haptic-hardware", qos: .userInitiated)
    private let lock = NSLock()
    private var activeToken: UUID?
    private var engine: CHHapticEngine?
    private var engineID = UUID()
    private var player: CHHapticAdvancedPatternPlayer?
    private var playerToken: UUID?
    private var completion: ((Error?) -> Void)?

    private func isActive(_ token: UUID) -> Bool { lock.withLock { activeToken == token } }

    func play(_ pattern: CompiledPattern, token: UUID, started: @escaping () -> Void, completed: @escaping (Error?) -> Void) {
        lock.withLock { activeToken = token }
        queue.async { [self] in
            guard isActive(token) else { return }
            do {
                if engine == nil {
                    // Haptics do not depend on the success sound's AVAudioSession.
                    let created = try CHHapticEngine(audioSession: nil)
                    created.playsHapticsOnly = true
                    created.isAutoShutdownEnabled = true
                    let id = UUID(); engineID = id
                    created.stoppedHandler = { [weak self] _ in
                        guard let self else { return }
                        let stoppedToken = self.lock.withLock { self.activeToken }
                        self.queue.async {
                            guard self.engineID == id, let stoppedToken, self.isActive(stoppedToken) else { return }
                            self.completion?(PlaybackError.interrupted)
                        }
                    }
                    created.resetHandler = { [weak self] in
                        guard let self else { return }
                        self.queue.async {
                            guard self.engineID == id else { return }
                            self.engine = nil
                            if let playerToken = self.playerToken, self.isActive(playerToken) { self.completion?(PlaybackError.interrupted) }
                        }
                    }
                    engine = created
                }
                guard isActive(token), let engine else { return }
                completion = completed; playerToken = token
                engine.start { [weak self] error in
                    guard let self else { return }
                    self.queue.async {
                        guard self.isActive(token) else { return }
                        if let error { completed(error); return }
                        do {
                            let newPlayer = try engine.makeAdvancedPlayer(with: Self.makePattern(pattern))
                            guard self.isActive(token) else { return }
                            self.player = newPlayer
                            newPlayer.completionHandler = { error in completed(error) }
                            try newPlayer.start(atTime: CHHapticTimeImmediate)
                            guard self.isActive(token) else { try? newPlayer.stop(atTime: CHHapticTimeImmediate); return }
                            started()
                        } catch { completed(error) }
                    }
                }
            } catch { completed(error) }
        }
    }
    func finish(_ token: UUID, cancel: Bool) {
        lock.withLock { if activeToken == token { activeToken = nil } }
        queue.async { [self] in
            guard playerToken == token else { return }
            if cancel {
                try? player?.stop(atTime: CHHapticTimeImmediate)
                let previousEngine = engine
                engine = nil; engineID = UUID()
                previousEngine?.stop(completionHandler: nil)
            }
            player = nil; playerToken = nil; completion = nil
        }
    }
    private static func makePattern(_ pattern: CompiledPattern) throws -> CHHapticPattern {
        var events: [CHHapticEvent] = []
        var curves: [CHHapticParameterCurve] = []
        for pulse in pattern.pulses {
            events.append(CHHapticEvent(eventType: pulse.kind == .tap ? .hapticTransient : .hapticContinuous,
                parameters: [.init(parameterID: .hapticIntensity, value: Float(pulse.intensity)),
                             .init(parameterID: .hapticSharpness, value: Float(pulse.sharpness))],
                relativeTime: pulse.start, duration: pulse.duration))
            if pulse.kind == .continuous && pulse.envelope != .flat {
                let levels = pulse.envelope.levels
                let points = levels.enumerated().map { index, value in
                    CHHapticParameterCurve.ControlPoint(relativeTime: pulse.duration * Double(index) / Double(levels.count - 1), value: Float(value))
                }
                curves.append(.init(parameterID: .hapticIntensityControl, controlPoints: points, relativeTime: pulse.start))
            } else {
                curves.append(.init(parameterID: .hapticIntensityControl,
                    controlPoints: [.init(relativeTime: 0, value: 1), .init(relativeTime: max(0.06, pulse.duration), value: 1)], relativeTime: pulse.start))
            }
        }
        return try CHHapticPattern(events: events, parameterCurves: curves)
    }
}
