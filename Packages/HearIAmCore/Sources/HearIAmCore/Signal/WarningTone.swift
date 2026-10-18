import Foundation

/// Timbre of the obstacle warning beep. The first one tried (sharp) hurt the ears on AirPods (10/17),
/// so softer candidates are compared on the device before one is fixed.
public enum WarningTone: String, CaseIterable, Sendable {
    /// 950 Hz with a strong third harmonic. The original, kept for comparison.
    case sharp
    /// 880 Hz pure tone with slow edges.
    case soft
    /// 440 Hz, mostly pure, an octave lower.
    case low
    /// C5 (523 Hz) that dies away quickly, like a marimba tap. It was 660 Hz, the left direction beep.
    case pluck
    /// 60 Hz with a 240 Hz overtone: a short low thump, closer to a vibration than a beep.
    case thump

    /// Partials the beep is built from, loudest first. Kept here so they can be checked against the
    /// direction beep pitches.
    public var pitches: [Double] {
        switch self {
        case .sharp: return [950,2850]
        case .soft: return [880]
        case .low: return [440,880]
        case .pluck: return [523.25]
        case .thump: return [60,240]
        }
    }
}
