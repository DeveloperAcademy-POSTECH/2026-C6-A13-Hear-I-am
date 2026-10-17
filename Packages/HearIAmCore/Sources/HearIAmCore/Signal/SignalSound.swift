import Foundation

/// Obstacle warning stage. Closer stages repeat faster, like a parking sensor.
/// The distances that select a stage belong to the guidance rules, not to the sound.
public enum WarningLevel: Int, CaseIterable, Comparable, Sendable {
    case far=1, near, close
    /// Seconds from the start of one beep to the next.
    public var period: Double { [0.8,0.4,0.15][rawValue-1] }
    public var name: String { ["far","near","close"][rawValue-1] }
    public static func < (a: WarningLevel, b: WarningLevel) -> Bool { a.rawValue < b.rawValue }
}

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

/// Renders signal sounds as mono float samples. No sound files are bundled.
/// Every sound starts and ends at zero amplitude so looping or cutting it never clicks.
public enum ToneRenderer {
    public static let sampleRate=44_100.0
    public static let peak: Float=0.9
    static let warningHertz=950.0, warningPulse=0.08
    static let arrivalHertz=1318.5, arrivalLength=0.6
    static let buzzRate=12.0, buzzLength=0.6

    public static func render(_ sound: SignalSound) -> [Float] {
        switch sound {
        case .warning(let level):
            let pulse=samples(warningPulse) { t in
                let tone=sin(2 * .pi*warningHertz*t)+0.3*sin(2 * .pi*warningHertz*3*t)
                return tone*fade(t,length:warningPulse,edge:0.005)
            }
            return normalized(pulse)+[Float](repeating:0,count:max(0,count(level.period)-pulse.count))
        case .arrival:
            return normalized(samples(arrivalLength) { t in
                let tone=sin(2 * .pi*arrivalHertz*t)+0.4*sin(2 * .pi*arrivalHertz*2*t)
                return tone*exp(-t*7)*fade(t,length:arrivalLength,edge:0.003)
            })
        case .buzz(let hertz, let harmonic):
            return normalized(samples(buzzLength) { t in
                let pulse=0.5*(1-cos(2 * .pi*buzzRate*t))
                let tone=sin(2 * .pi*hertz*t)+(harmonic ? 0.35*sin(2 * .pi*hertz*4*t) : 0)
                return tone*pulse*fade(t,length:buzzLength,edge:0.01)
            })
        }
    }

    static func count(_ seconds: Double) -> Int { Int((seconds*sampleRate).rounded()) }
    private static func samples(_ seconds: Double, _ value: (Double) -> Double) -> [Float] {
        (0..<count(seconds)).map { Float(value(Double($0)/sampleRate)) }
    }
    /// Linear ramps at both ends; the last sample lands exactly on zero.
    private static func fade(_ t: Double, length: Double, edge: Double) -> Double {
        let end=length-1/sampleRate
        return max(0,min(1,t/edge,(end-t)/edge))
    }
    private static func normalized(_ values: [Float]) -> [Float] {
        guard let top=values.map(abs).max(), top > 0 else { return values }
        return values.map { $0/top*peak }
    }
}
