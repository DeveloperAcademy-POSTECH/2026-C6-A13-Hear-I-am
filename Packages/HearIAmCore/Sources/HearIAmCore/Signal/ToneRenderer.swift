import Foundation

/// Renders signal sounds as mono float samples. No sound files are bundled.
/// Every sound starts and ends at zero amplitude so looping or cutting it never clicks.
public enum ToneRenderer {
    public static let sampleRate=44_100.0
    public static let peak: Float=0.9
    /// Rising G5–D6–G6 bells, with a longer tail on the final note.
    public static let arrivalLength=0.52, arrivalSpeechDelay=0.60
    static let arrivalPitches=[784.0,1174.66,1568.0]
    static let alignmentHertz=1568.0
    static let buzzRate=12.0, buzzLength=0.6

    public static func render(_ sound: SignalSound) -> [Float] {
        switch sound {
        case .warning(let level, let tone):
            let pulse=normalized(warningBeep(tone))
            return pulse+[Float](repeating:0,count:max(0,count(level.period)-pulse.count))
        case .arrival:
            return normalized(samples(arrivalLength) { t in
                var value=0.0
                for (index,hertz) in arrivalPitches.enumerated() {
                    let local=t-Double(index)*0.11
                    let length=index == 2 ? 0.30 : 0.20
                    guard local >= 0, local < length else { continue }
                    let phase=2 * Double.pi*hertz*local
                    let tone=sin(phase)+0.2*sin(phase*2)
                    value += tone*exp(-local*10)*fade(local,length:length,edge:0.006)
                }
                return value
            })
        case .directionSweep(let sweep):
            let duration=DirectionSweep.duration
            let slope=(sweep.endHertz-sweep.startHertz)/duration
            return normalized(samples(duration) { t in
                // Integrating frequency gives a continuous phase without clicks or pitch jumps.
                let phase=2 * Double.pi*(sweep.startHertz*t+0.5*slope*t*t)
                return sin(phase)*fade(t,length:duration,edge:0.02)
            })
        case .directionAligned:
            let length=0.10, gap=0.09, period=length+gap
            return normalized(samples(2*length+gap) { t in
                let within=t.truncatingRemainder(dividingBy:period)
                guard within < length else { return 0 }
                return sin(2 * .pi*1100*t)*fade(within,length:length,edge:0.01)
            })
        case .directionBuzz(let hertz):
            guard SteppedDirectionGate.pitches.contains(hertz) else { return [] }
            return harmonicBurst(Double(hertz))
        case .directionBuzzAligned:
            return harmonicBurst(60)+[Float](repeating:0,count:count(SteppedDirectionGate.alignmentGap))+render(.countDirectionAligned)
        case .countDirectionAligned:
            let length=CountedDirectionGate.alignmentLength
            return normalized(samples(length) { t in
                let tone=sin(2 * .pi*alignmentHertz*t)+0.4*sin(2 * .pi*alignmentHertz*2*t)
                return tone*exp(-t*7)*fade(t,length:length,edge:0.003)
            })
        case .countDirection(let right, let count):
            guard (1...3).contains(count) else { return [] }
            let hertz=right ? CountedDirectionGate.rightHertz : CountedDirectionGate.leftHertz
            let length=CountedDirectionGate.beepLength, gap=CountedDirectionGate.beepGap
            let period=length+gap, total=Double(count)*length+Double(count-1)*gap
            return normalized(samples(total) { t in
                let within=t.truncatingRemainder(dividingBy:period)
                guard within < length else { return 0 }
                return sin(2 * .pi*hertz*t)*fade(within,length:length,edge:0.01)
            })
        case .direction(let degrees):
            guard let beep=DirectionPattern.beep(signedDegrees:degrees) else { return [] }
            let length=DirectionPattern.beepLength, period=length+DirectionPattern.beepGap
            let total=Double(beep.count)*length+Double(beep.count-1)*DirectionPattern.beepGap
            return normalized(samples(total) { t in
                let within=t.truncatingRemainder(dividingBy:period)
                guard within < length else { return 0 }
                return sin(2 * .pi*beep.hertz*t)*fade(within,length:length,edge:0.008)
            })
        case .buzz(let hertz, let harmonic):
            return normalized(samples(buzzLength) { t in
                let pulse=0.5*(1-cos(2 * .pi*buzzRate*t))
                let tone=sin(2 * .pi*hertz*t)+(harmonic ? 0.35*sin(2 * .pi*hertz*4*t) : 0)
                return tone*pulse*fade(t,length:buzzLength,edge:0.01)
            })
        }
    }

    /// The existing high-harmonic buzz timbre, shortened to exactly three 12 Hz pulses.
    static func harmonicBurst(_ hertz: Double) -> [Float] {
        let length=SteppedDirectionGate.burstLength
        return normalized(samples(length) { t in
            let pulse=0.5*(1-cos(2 * .pi*buzzRate*t))
            let tone=sin(2 * .pi*hertz*t)+0.35*sin(2 * .pi*hertz*4*t)
            return tone*pulse*fade(t,length:length,edge:0.01)
        })
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
