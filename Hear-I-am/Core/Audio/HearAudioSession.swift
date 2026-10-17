import AVFoundation

/// The one audio session setup shared by speech and signal tones, so both can sound at the same time.
@MainActor enum HearAudioSession {
    private(set) static var active=false

    static func activate() throws {
        guard !active else { return }
        let audio=AVAudioSession.sharedInstance()
        try audio.setCategory(.playback,mode:.spokenAudio,options:[.mixWithOthers])
        try audio.setActive(true);active=true
    }
    static func deactivate() {
        active=false
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
    }
    /// The system already deactivated the session; the next activate() sets it up again.
    static func interrupted() { active=false }

    /// Output names for logs, e.g. "Headphones:AirPods Pro" or "Speaker:Speaker".
    static var route: String {
        AVAudioSession.sharedInstance().currentRoute.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator:",")
    }
}

/// Fixed loudness per signal: warning > speech > arrival. Overall level is set with the phone volume at rehearsal.
enum SignalVolume {
    static let warning: Float=1.0
    static let speech: Float=0.8
    static let buzz: Float=0.9
    static let arrival: Float=0.5
    /// Tones drop to this share of their level while speech plays, so words are not masked.
    static let duckedShare: Float=0.6
    /// Warning level after 10 s of failing to step away from an obstacle.
    static let quietShare: Float=0.3
}
