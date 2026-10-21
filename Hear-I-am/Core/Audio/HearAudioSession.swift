import AVFoundation

/// The one audio session setup shared by speech and signal tones, so both can sound at the same time.
@MainActor enum HearAudioSession {
    private(set) static var active=false
    /// The output the active session was set up for; a changed setting is applied on the next sound.
    private static var configuredForSpeaker: Bool?

    /// Plays through the phone speaker even when AirPods are connected (10/19, so signals can be tried
    /// with or without earbuds). Off: the connected AirPods, or the speaker when none is connected.
    static let speakerKey="audio.forceSpeaker"
    static var forcesSpeaker: Bool { UserDefaults.standard.bool(forKey:speakerKey) }

    static func activate() throws {
        let speaker=forcesSpeaker
        guard !active || configuredForSpeaker != speaker else { return }
        let audio=AVAudioSession.sharedInstance()
        if speaker {
            // .playback cannot override the route. .playAndRecord without Bluetooth options leaves only
            // the built-in outputs, and .defaultToSpeaker picks the speaker over the receiver. Input is never used.
            try audio.setCategory(.playAndRecord,mode:.default,options:[.defaultToSpeaker,.mixWithOthers])
        } else {
            try audio.setCategory(.playback,mode:.spokenAudio,options:[.mixWithOthers])
        }
        try audio.setActive(true);active=true;configuredForSpeaker=speaker
    }
    static func deactivate() {
        active=false;configuredForSpeaker=nil
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
    }
    /// The system already deactivated the session; the next activate() sets it up again.
    static func interrupted() { active=false;configuredForSpeaker=nil }

    /// Output names for logs, e.g. "Headphones:AirPods Pro" or "Speaker:Speaker".
    static var route: String {
        AVAudioSession.sharedInstance().currentRoute.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator:",")
    }
}

/// Fixed loudness per signal. Overall level is set with the phone volume at rehearsal.
/// The arrival ding sits a little under the warning since 10/21 so the side of the next point is heard over it.
enum SignalVolume {
    static let warning: Float=1.0
    static let speech: Float=0.8
    static let buzz: Float=0.9
    /// It was 1.0 like the warning (10/17) until 10/21, when it masked the side of the next point.
    static let arrival: Float=0.7
    /// 「오른쪽」·「왼쪽」 for the next point: full speech volume (10/21).
    static let nextSide: Float=1.0
    /// Below the warning, like speech: the direction beep should not hide how close an obstacle is.
    static let direction: Float=0.8
    /// Tones drop to this share of their level while speech plays, so words are not masked.
    /// The arrival ding is the exception (10/19).
    static let duckedShare: Float=0.6
    /// Warning level after 10 s of failing to step away from an obstacle.
    static let quietShare: Float=0.3
}
