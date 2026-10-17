import Foundation

/// Every non-speech sound the performer hears through the earbud.
public enum SignalSound: Equatable, Sendable {
    /// One period of the looping warning: a short beep followed by silence.
    case warning(WarningLevel, tone: WarningTone = .soft)
    /// A single bell-like ding when a point is reached.
    case arrival
    /// Direction beep for a 45° landmark; see DirectionPattern.beep.
    case direction(signedDegrees: Int)
    /// A low tone pulsed about 12 times a second so it reads as a buzz rather than a note.
    /// `harmonic` mixes in a quieter copy two octaves up for earbuds that cannot reproduce the low end.
    case buzz(hertz: Double, harmonic: Bool)

    /// Stable identifier for logs.
    public var name: String {
        switch self {
        case .warning(let level, let tone): return "warning_\(level.name)_\(tone.rawValue)"
        case .arrival: return "arrival"
        case .direction(let degrees): return "direction_"+DirectionPattern.name(signedDegrees:degrees)
        case .buzz(let hertz, let harmonic): return "buzz_\(Int(hertz))hz"+(harmonic ? "_harmonic" : "")
        }
    }
}
