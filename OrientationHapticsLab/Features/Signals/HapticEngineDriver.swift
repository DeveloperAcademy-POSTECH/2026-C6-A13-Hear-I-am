import CoreHaptics
import Foundation

struct HapticPulse: Sendable {
    let time: TimeInterval
    let duration: TimeInterval
    let intensity: Float
    let sharpness: Float
}

enum HapticDriverEvent: Sendable {
    case ready
    case playing
    case finished
    case failed(String)
}

typealias HapticReply = @Sendable (UInt, HapticDriverEvent) -> Void

protocol HapticDriving: Sendable {
    func prepare(revision: UInt, reply: @escaping HapticReply) async
    func play(_ pulses: [HapticPulse], revision: UInt, reply: @escaping HapticReply) async
    func cancel(revision: UInt, suspend: Bool) async
}

/// Core Haptics objects live on this actor, never on the UI actor.
actor HapticEngineDriver: HapticDriving {
    private var engine: CHHapticEngine?
    private var player: (any CHHapticAdvancedPatternPlayer)?
    private var revision: UInt = 0
    private var engineEpoch: UInt = 0
    private var ready = false
    private var starting = false
    private var pending: [HapticPulse]?
    private var reply: HapticReply?

    func prepare(revision: UInt, reply: @escaping HapticReply) {
        guard revision >= self.revision else { return }
        self.revision = revision
        self.reply = reply
        startIfNeeded()
    }

    func play(_ pulses: [HapticPulse], revision: UInt, reply: @escaping HapticReply) {
        guard revision >= self.revision else { return }
        self.revision = revision
        self.reply = reply
        try? player?.cancel()
        player = nil
        pending = pulses
        startIfNeeded()
    }

    func cancel(revision: UInt, suspend: Bool) {
        guard revision >= self.revision else { return }
        self.revision = revision
        pending = nil
        reply = nil
        try? player?.cancel()
        player = nil
        if suspend {
            engineEpoch &+= 1
            engine?.stop(completionHandler: nil)
            engine = nil
            ready = false
            starting = false
        }
    }

    private func startIfNeeded() {
        if ready { beginPending(); return }
        guard !starting else { return }
        do {
            if engine == nil {
                let created = try CHHapticEngine()
                created.playsHapticsOnly = true
                created.isMutedForAudio = true
                // Keep the short experiment's engine warm; suspend explicitly on background.
                created.isAutoShutdownEnabled = false
                engine = created
            }
            guard let engine else { return }
            engineEpoch &+= 1
            let epoch = engineEpoch
            engine.stoppedHandler = { @Sendable [weak self] _ in
                Task { await self?.engineStopped(epoch: epoch) }
            }
            engine.resetHandler = { @Sendable [weak self] in
                Task { await self?.engineStopped(epoch: epoch) }
            }
            starting = true
            engine.start { @Sendable [weak self] error in
                let message = error?.localizedDescription
                Task { await self?.engineStarted(epoch: epoch, error: message) }
            }
        } catch {
            pending = nil
            ready = false
            starting = false
            reply?(revision, .failed(error.localizedDescription))
        }
    }

    private func engineStarted(epoch: UInt, error: String?) {
        guard epoch == engineEpoch else { return }
        starting = false
        if let error {
            pending = nil
            ready = false
            reply?(revision, .failed(error))
            return
        }
        ready = true
        reply?(revision, .ready)
        beginPending()
    }

    private func engineStopped(epoch: UInt) {
        guard epoch == engineEpoch else { return }
        engineEpoch &+= 1
        ready = false
        starting = false
        pending = nil
        player = nil
        reply?(revision, .failed("진동이 중단됐어요. 다음 신호에서 다시 준비합니다."))
    }

    private func beginPending() {
        guard let pulses = pending, let engine else {
            reply?(revision, .ready)
            return
        }
        pending = nil
        let token = revision
        do {
            let events = pulses.map {
                CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: $0.intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: $0.sharpness)
                ], relativeTime: $0.time, duration: $0.duration)
            }
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let created = try engine.makeAdvancedPlayer(with: pattern)
            created.completionHandler = { @Sendable [weak self] error in
                let message = error?.localizedDescription
                Task { await self?.completed(revision: token, error: message) }
            }
            player = created
            try created.start(atTime: CHHapticTimeImmediate)
            reply?(token, .playing)
        } catch {
            player = nil
            reply?(token, .failed(error.localizedDescription))
        }
    }

    private func completed(revision: UInt, error: String?) {
        guard revision == self.revision else { return }
        player = nil
        reply?(revision, error.map(HapticDriverEvent.failed) ?? .finished)
    }
}
