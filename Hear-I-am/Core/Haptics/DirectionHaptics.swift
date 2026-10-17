import CoreHaptics
import os
import HearIAmCore

/// Plays the PoC1 direction vibration on the waist phone. A new pattern cancels the previous one.
/// Devices without haptics stay silent and log once. Every play, stop and failure is logged.
@MainActor final class DirectionHaptics {
    /// (event, detail) for the experiment log, like SignalPlayer.onEvent.
    var onEvent: ((String,String)->Void)?
    let supported=CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var reportedUnsupported=false
    private let log=Logger(subsystem:Bundle.main.bundleIdentifier ?? "HearIAm",category:"Haptics")

    /// Plays the pattern for a 30° landmark; other angles are ignored.
    func play(signedDegrees: Int) {
        let name=DirectionPattern.name(signedDegrees:signedDegrees)
        guard supported else {
            if !reportedUnsupported { reportedUnsupported=true;event("haptic_unsupported",name) }
            return
        }
        guard let pulses=DirectionPattern.pulses(signedDegrees:signedDegrees) else {
            event("haptic_error","\(signedDegrees) is not a 30° landmark",level:.error);return
        }
        do {
            let engine=try prepare()
            try? player?.cancel()
            let events=pulses.map {
                CHHapticEvent(eventType:.hapticContinuous,parameters:[
                    CHHapticEventParameter(parameterID:.hapticIntensity,value:$0.intensity),
                    CHHapticEventParameter(parameterID:.hapticSharpness,value:$0.sharpness)
                ],relativeTime:$0.time,duration:$0.duration)
            }
            let next=try engine.makeAdvancedPlayer(with:CHHapticPattern(events:events,parameters:[]))
            try next.start(atTime:CHHapticTimeImmediate)
            player=next
            event("haptic_play",name)
        } catch {
            player=nil;self.engine=nil
            event("haptic_error","\(name) \(error.localizedDescription)",level:.error)
        }
    }
    func stop() { try? player?.cancel();player=nil }
    /// Stops the engine, e.g. when the screen closes or the app leaves the foreground.
    func shutdown() {
        stop();engine?.stop(completionHandler:nil);engine=nil
        event("haptic_engine","stopped")
    }

    private func prepare() throws -> CHHapticEngine {
        if let engine { return engine }
        let created=try CHHapticEngine()
        created.playsHapticsOnly=true
        created.isAutoShutdownEnabled=false
        created.stoppedHandler={ [weak self] reason in
            Task { @MainActor in self?.engineLost("stopped reason=\(reason.rawValue)") }
        }
        created.resetHandler={ [weak self] in
            Task { @MainActor in self?.engineLost("reset") }
        }
        try created.start()
        engine=created
        event("haptic_engine","started")
        return created
    }
    /// The next play() builds a fresh engine.
    private func engineLost(_ detail: String) {
        engine=nil;player=nil
        event("haptic_engine",detail,level:.error)
    }
    private func event(_ name: String, _ detail: String, level: OSLogType = .info) {
        log.log(level:level,"\(name, privacy:.public) \(detail, privacy:.public)")
        onEvent?(name,detail)
    }
}
