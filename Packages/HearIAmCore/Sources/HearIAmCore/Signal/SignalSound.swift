import Foundation

/// Every non-speech sound the performer hears through the earbud.
public enum SignalSound: Equatable, Sendable {
    /// One period of the looping warning: a short rough beep followed by silence.
    case warning(WarningLevel)
    /// A single bell-like ding when a point is reached.
    case arrival
    /// A low tone pulsed about 12 times a second so it reads as a buzz rather than a note.
    /// `harmonic` mixes in a quieter copy two octaves up for earbuds that cannot reproduce the low end.
    case buzz(hertz: Double, harmonic: Bool)

    /// Stable identifier for logs.
    public var name: String {
        switch self {
        case .warning(let level): return "warning_"+level.name
        case .arrival: return "arrival"
        case .buzz(let hertz, let harmonic): return "buzz_\(Int(hertz))hz"+(harmonic ? "_harmonic" : "")
        }
    }
}
