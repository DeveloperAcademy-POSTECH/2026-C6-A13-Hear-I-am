import Foundation

/// Every non-speech sound the performer hears through the earbud.
public enum SignalSound: Equatable, Sendable {
    /// One period of the looping warning: a short beep followed by silence.
    case warning(WarningLevel, tone: WarningTone = .soft)
    /// A single bell-like ding when a point is reached.
    case arrival
    /// Rising for left, falling for right; width encodes remaining angle.
    case directionSweep(DirectionSweep)
    /// Two short equal-pitch beeps: heading aligned, not waypoint arrival.
    case directionAligned
    /// Three pulses with the same higher harmonic as the sound-test buzz.
    case directionBuzz(hertz: Int)
    /// One 60 Hz pulse group, then the alignment bell.
    case directionBuzzAligned
    /// Test-only fixed-pitch group: left high, right low, 1–3 discrete beeps.
    case countDirection(toRight: Bool, count: Int)
    /// Cancellable alignment bell on the direction channel, followed by silence.
    case countDirectionAligned
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
        case .directionSweep(let sweep): return "direction_sweep_\(sweep.turn.rawValue)_\(sweep.extent)"
        case .directionAligned: return "direction_aligned"
        case .directionBuzz(let hertz): return "direction_buzz_\(hertz)hz_harmonic"
        case .directionBuzzAligned: return "direction_buzz_aligned_60hz_bell"
        case .countDirection(let right, let count): return "count_direction_\(right ? "right" : "left")_\(count)"
        case .countDirectionAligned: return "count_direction_aligned_bell"
        case .direction(let degrees): return "direction_"+DirectionPattern.name(signedDegrees:degrees)
        case .buzz(let hertz, let harmonic): return "buzz_\(Int(hertz))hz"+(harmonic ? "_harmonic" : "")
        }
    }
}
