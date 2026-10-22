import Foundation

/// Timbre of the confirmation sound played the moment direction ticks stop because the body faces the target (#62).
/// Earlier versions used 990 Hz (flat beep) and F5→C6 (698→1046.5 Hz), which felt piercing on AirPods.
/// All candidates sit in the comfortable low-to-mid register and stay >10% away from ticks, warnings and the arrival ding.
public enum AlignedTone: String, CaseIterable, Sendable {
    /// Db4 → F4 (277.18 → 349.23 Hz): warm marimba major third ("딩-동"), soft and confirming without high frequencies.
    case warm
    /// G3 → D4 (196.0 → 293.66 Hz): deep wooden perfect fifth, similar to an earbud connection chime.
    case fifth
    /// Db4 + F4 (277.18 + 349.23 Hz): two warm notes sounding together as a gentle chord pad.
    case chord
    /// E4 → E5 (329.63 → 659.25 Hz): clearer mid-range octave chime, still well below 1 kHz.
    case softBell

    /// Fundamental pitches used by the candidate, checked against ticks, warnings and the arrival ding.
    public var pitches: [Double] {
        switch self {
        case .warm: return [277.18,349.23]
        case .fifth: return [196.0,293.66]
        case .chord: return [277.18,349.23]
        case .softBell: return [329.63,659.25]
        }
    }
}
