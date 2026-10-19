import Foundation

/// Renders signal sounds as mono float samples. No sound files are bundled.
/// Every sound starts and ends at zero amplitude so looping or cutting it never clicks.
public enum ToneRenderer {
    public static let sampleRate=44_100.0
    public static let peak: Float=0.9
    /// G6. It was E6 (1318.5 Hz) until 10/18, almost the right direction beep (1320 Hz).
    /// Since 10/19 it rings for 1 s with two overtones instead of 0.6 s with one, so it carries more
    /// energy at the same peak: the performer walked past points without noticing it.
    static let arrivalHertz=1568.0, arrivalLength=1.0, arrivalDecay=4.0
    static let buzzRate=12.0, buzzLength=0.6

    public static func render(_ sound: SignalSound) -> [Float] {
        switch sound {
        case .warning(let level, let tone):
            let pulse=normalized(warningBeep(tone))
            return pulse+[Float](repeating:0,count:max(0,count(level.period)-pulse.count))
        case .arrival:
            return normalized(samples(arrivalLength) { t in
                let tone=sin(2 * .pi*arrivalHertz*t)+0.5*sin(2 * .pi*arrivalHertz*2*t)+0.2*sin(2 * .pi*arrivalHertz*3*t)
                return tone*exp(-t*arrivalDecay)*fade(t,length:arrivalLength,edge:0.003)
            })
        case .direction(let degrees, let style):
            guard let beep=DirectionPattern.beep(signedDegrees:degrees,style:style) else { return [] }
            let length=DirectionPattern.beepLength, period=length+DirectionPattern.beepGap
            let total=Double(beep.count)*length+Double(beep.count-1)*DirectionPattern.beepGap
            let rendered=normalized(samples(total) { t in
                let within=t.truncatingRemainder(dividingBy:period)
                guard within < length else { return 0 }
                let strike=style == .pluck ? exp(-within*25) : 1
                return sin(2 * .pi*beep.hertz*t)*strike*fade(within,length:length,edge:style == .pluck ? 0.002 : 0.008)
            })
            return style == .quiet ? rendered.map { $0*0.5 } : rendered
        case .buzz(let hertz, let harmonic):
            return normalized(samples(buzzLength) { t in
                let pulse=0.5*(1-cos(2 * .pi*buzzRate*t))
                let tone=sin(2 * .pi*hertz*t)+(harmonic ? 0.35*sin(2 * .pi*hertz*4*t) : 0)
                return tone*pulse*fade(t,length:buzzLength,edge:0.01)
            })
        }
    }

    /// One beep, no longer than the shortest warning period (0.15 s).
    static func warningBeep(_ tone: WarningTone) -> [Float] {
        func sine(_ hertz: Double, _ t: Double) -> Double { sin(2 * .pi*hertz*t) }
        let p=tone.pitches
        switch tone {
        case .sharp:
            return samples(0.08) { t in (sine(p[0],t)+0.3*sine(p[1],t))*fade(t,length:0.08,edge:0.005) }
        case .soft:
            return samples(0.1) { t in sine(p[0],t)*fade(t,length:0.1,edge:0.02) }
        case .low:
            return samples(0.12) { t in (sine(p[0],t)+0.15*sine(p[1],t))*fade(t,length:0.12,edge:0.02) }
        case .pluck:
            return samples(0.14) { t in sine(p[0],t)*exp(-t*30)*fade(t,length:0.14,edge:0.003) }
        case .thump:
            return samples(0.12) { t in (sine(p[0],t)+0.4*sine(p[1],t))*fade(t,length:0.12,edge:0.015) }
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
