import Foundation

/// Direction vibration as used in the PoC1 field test (10/12), with 0° = the next target.
/// PoC1 let each angle pick a rhythm in its settings; the field assignment, confirmed on 10/17, is
/// 0°: long · 45°: one short · 90°: two short · 135°: three short · 180°: long.
/// Left and right share a rhythm, as on the field. Rhythm timings are PoC1's "기존 리듬" presets
/// (single · double · triple · long, branch poc/1-orientation-haptics HapticService), at full intensity.
public enum DirectionPattern {
    public static let landmarks=[0,45,90,135,180,-135,-90,-45]
    static let intensity: Float=1.0, sharpness: Float=0.8
    static let shortPulse=0.065, shortGap=0.13, longPulse=0.30

    /// nil for angles that are not a 45° landmark. Positive is right, negative is left.
    public static func pulses(signedDegrees: Int) -> [DirectionPulse]? {
        let degrees=signedDegrees == -180 ? 180 : signedDegrees
        guard landmarks.contains(degrees) else { return nil }
        let magnitude=abs(degrees)
        if magnitude == 0 || magnitude == 180 {
            return [DirectionPulse(time:0,duration:longPulse,intensity:intensity,sharpness:sharpness)]
        }
        return (0..<magnitude/45).map {
            DirectionPulse(time:Double($0)*shortGap,duration:shortPulse,intensity:intensity,sharpness:sharpness)
        }
    }
    // Direction beep (#33, decided 10/18): PoC1's beep rule, played at the same landmarks as the
    // vibration. Left is low, right is high, front and back sit between them; front sounds once,
    // back twice, a side once per 45°. PoC1 used 440 · 660 · 880 Hz; every pitch is raised by half so
    // none is shared with the 「낮은 삑」 warning (440 Hz with an 880 Hz overtone).
    public static let leftHertz=660.0, centerHertz=990.0, rightHertz=1320.0
    /// PoC1 beep timings (AudioCue: 0.16 s on, 0.12 s off).
    public static let beepLength=0.16, beepGap=0.12

    /// Pitch and number of beeps; nil for angles that are not a 45° landmark.
    public static func beep(signedDegrees: Int) -> (hertz: Double, count: Int)? {
        let degrees=signedDegrees == -180 ? 180 : signedDegrees
        guard landmarks.contains(degrees) else { return nil }
        if degrees == 0 { return (centerHertz,1) }
        if degrees == 180 { return (centerHertz,2) }
        return (degrees < 0 ? leftHertz : rightHertz,abs(degrees)/45)
    }
    /// Readable label for logs, e.g. "left_90" or "front".
    public static func name(signedDegrees: Int) -> String {
        let degrees=signedDegrees == -180 ? 180 : signedDegrees
        if degrees == 0 { return "front" }
        if degrees == 180 { return "back" }
        return (degrees < 0 ? "left_" : "right_")+String(abs(degrees))
    }
}

/// What carries the direction at each 45° landmark (#33): the waist vibration, the earbud beep, or both.
/// Chosen in the sound test tab and saved, so guidance uses the same.
public enum DirectionSignalMode: String, CaseIterable, Sendable {
    case haptic, beep, both
    public var vibrates: Bool { self != .beep }
    public var beeps: Bool { self != .haptic }
}
