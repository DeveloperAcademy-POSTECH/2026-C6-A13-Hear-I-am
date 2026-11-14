import Foundation

/// Tells a person speaking over the app from the app's own voice coming back through the microphone.
///
/// Echo cancellation leaves part of the app's voice in the microphone on the speaker, and the recognizer
/// writes it down (11/13 POS: 「Yes, what would you like to do」 came back almost word for word, in Korean
/// 「네, 무엇을 드릴까요」). What is left is quieter than the app's output by a nearly fixed amount, while a person
/// at the phone is about as loud as the output or louder. So the microphone level is compared with the
/// loudest app output just before it, with the phone volume taken out.
///
/// Measured on POS (iPhone 16 Pro Max, speaker, automatic gain off), microphone minus output in dB plus the
/// volume correction, loudest 0.1 s frame of a line: the app alone −13 to −3, a person saying 「스캔」 or
/// 「practice」 at the phone +2 to +14. The margin sits between them, and two frames in a row are needed.
public struct VoiceTalkOver {
    public static let margin: Double = 3
    public static let frames = 2
    /// The app's output stays in the comparison this long; the echo arrives within it.
    public static let window: Double = 0.3
    /// Quieter than this, the app is not speaking and there is nothing to tell apart.
    public static let silentOutput: Double = -50

    private var outputs: [(time: Double, level: Double)] = []
    private var run = 0
    /// The phone's volume, 0–1. The echo grows with it while the app's output level does not.
    public var volume: Double = 1

    public init() {}

    public static func decibels(_ rms: Double) -> Double { 20 * log10(max(rms, 1e-6)) }

    public mutating func output(rms: Double, at time: Double) {
        outputs.append((time, Self.decibels(rms)))
        outputs.removeAll { $0.time < time - 1 }
    }

    /// True on the frame where a person is first heard over the app's voice.
    public mutating func input(rms: Double, at time: Double) -> Bool {
        let recent = outputs.filter { $0.time >= time - Self.window && $0.time <= time + 0.05 }
        guard let loudest = recent.map(\.level).max(), loudest > Self.silentOutput else { run = 0; return false }
        let over = Self.decibels(rms) - loudest - Self.decibels(max(volume, 0.05))
        guard over > Self.margin else { run = 0; return false }
        run += 1
        return run == Self.frames
    }

    public mutating func reset() { outputs.removeAll(); run = 0 }
}
