import Foundation

/// Renders signal sounds as mono float samples. No sound files are bundled.
/// Every sound starts and ends at zero amplitude so looping or cutting it never clicks.
public enum ToneRenderer {
    public static let sampleRate=44_100.0
    public static let peak: Float=0.9
    /// G4 with its octave, like a small singing bowl. It was E6 (1318.5 Hz) until 10/18, then G6 (1568 Hz)
    /// with overtones at 2× and 3×, then D6 (1174.66 Hz), both still tiring to hear (10/21). It rings for
    /// 1.2 s (0.6 s until 10/19, when the performer walked past points without noticing it) and swells in
    /// over 15 ms, so nothing stings.
    static let arrivalHertz=392.0, arrivalLength=1.2, arrivalDecay=3.0, arrivalAttack=0.015
    /// Db4 then F4 (277.18 → 349.23 Hz), a warm marimba major third (#62). It was F5→C6 (698.46→1046.5 Hz)
    /// on 10/21, whose 1–2 kHz energy still stung the ears on AirPods. Every AlignedTone pitch stays >10%
    /// from every tick, warning and the arrival pitch.
    public static let alignedHertz=AlignedTone.warm.pitches
    static let alignedNote=0.16, alignedStep=0.09
    static let buzzRate=12.0, buzzLength=0.6
    public static let tickLeftHertz=587.33, tickRightHertz=783.99, tickLength=0.045

    public static func render(_ sound: SignalSound) -> [Float] {
        switch sound {
        case .warning(let level, let tone):
            let pulse=normalized(warningBeep(tone))
            return pulse+[Float](repeating:0,count:max(0,count(level.period)-pulse.count))
        case .arrival:
            return normalized(samples(arrivalLength) { t in
                let tone=sin(2 * .pi*arrivalHertz*t)+0.45*sin(2 * .pi*arrivalHertz*2*t)
                return tone*exp(-t*arrivalDecay)*fade(t,length:arrivalLength,edge:arrivalAttack)
            })
        case .aligned(let tone):
            return normalized(alignedChime(tone))
        case .direction(let degrees):
            guard let beep=DirectionPattern.beep(signedDegrees:degrees) else { return [] }
            let length=DirectionPattern.beepLength, period=length+DirectionPattern.beepGap
            let total=Double(beep.count)*length+Double(beep.count-1)*DirectionPattern.beepGap
            return normalized(samples(total) { t in
                let within=t.truncatingRemainder(dividingBy:period)
                guard within < length else { return 0 }
                return sin(2 * .pi*beep.hertz*t)*fade(within,length:length,edge:0.008)
            })
        case .directionTick(let toRight):
            let f=toRight ? tickRightHertz : tickLeftHertz
            return normalized(samples(tickLength) { t in
                let body=sin(2 * .pi*f*t)+0.25*sin(2 * .pi*f*2.4*t)
                return body*exp(-t*65)*fade(t,length:tickLength,edge:0.002)
            })
        case .buzz(let hertz, let harmonic):
            return normalized(samples(buzzLength) { t in
                let pulse=0.5*(1-cos(2 * .pi*buzzRate*t))
                let tone=sin(2 * .pi*hertz*t)+(harmonic ? 0.35*sin(2 * .pi*hertz*4*t) : 0)
                return tone*pulse*fade(t,length:buzzLength,edge:0.01)
            })
        }
    }

    /// Soft confirmation chime when the body aligns with the target (#62).
    static func alignedChime(_ tone: AlignedTone) -> [Float] {
        let p=tone.pitches
        let total=alignedStep*Double(p.count-1)+alignedNote
        switch tone {
        case .warm:
            // Db4 → F4 (277.18 → 349.23 Hz): warm marimba major third, 12 ms soft attack, minimal overtone.
            return samples(total) { t in
                p.enumerated().reduce(0) { sum, note in
                    let local=t-alignedStep*Double(note.offset)
                    guard local >= 0, local < alignedNote else { return sum }
                    let body=sin(2 * .pi*note.element*local)+0.06*sin(2 * .pi*note.element*2*local)
                    return sum+body*exp(-local*18)*fade(local,length:alignedNote,edge:0.012)
                }
            }
        case .fifth:
            // G3 → D4 (196.0 → 293.66 Hz): deep wooden fifth; a warm octave partial helps small speakers.
            return samples(total) { t in
                p.enumerated().reduce(0) { sum, note in
                    let local=t-alignedStep*Double(note.offset)
                    guard local >= 0, local < alignedNote else { return sum }
                    let body=sin(2 * .pi*note.element*local)+0.22*sin(2 * .pi*note.element*2*local)
                    return sum+body*exp(-local*16)*fade(local,length:alignedNote,edge:0.014)
                }
            }
        case .chord:
            // Db4 + F4 sounding together as a soft warm chord pad with a 20 ms swell.
            return samples(total) { t in
                let chord=0.55*sin(2 * .pi*p[0]*t)+0.45*sin(2 * .pi*p[1]*t)
                return chord*exp(-t*13)*fade(t,length:total,edge:0.020)
            }
        case .softBell:
            // E4 → E5 (329.63 → 659.25 Hz): pure sine octave chime without upper harmonics.
            return samples(total) { t in
                p.enumerated().reduce(0) { sum, note in
                    let local=t-alignedStep*Double(note.offset)
                    guard local >= 0, local < alignedNote else { return sum }
                    return sum+sin(2 * .pi*note.element*local)*exp(-local*19)*fade(local,length:alignedNote,edge:0.012)
                }
            }
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
