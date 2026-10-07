import Foundation

enum SignalMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case haptic
    case speech
    case beep

    var id: String { rawValue }
    var title: String {
        switch self {
        case .haptic: "진동"
        case .speech: "음성"
        case .beep: "비프음"
        }
    }

    var explanation: String {
        switch self {
        case .haptic: "각도별로 지정한 진동 패턴과 세기로 알려요."
        case .speech: "‘왼쪽 30도’처럼 방향과 각도를 한국어로 읽어 줘요."
        case .beep: "왼쪽은 낮은 음, 오른쪽은 높은 음이에요. 30°는 1회, 45°는 2회, 90°는 3회 울려요."
        }
    }

    @MainActor var resetDescription: String {
        switch self {
        case .haptic: HapticService.resetPatternDescription
        case .speech: "‘기준 방향을 0도로 설정했어요’"
        case .beep: "중간 높이의 긴 소리 한 번"
        }
    }
}

/// One definition drives speech, beep generation, and the descriptions in settings.
struct AudioCue: Equatable, Sendable {
    let speech: String
    let frequency: Double
    let count: Int
    let pulseDuration: Double
    let gap: Double

    static func angle(_ signedDegrees: Double) -> AudioCue? {
        guard signedDegrees.isFinite,
              let magnitude = [30, 45, 90].first(where: { abs(abs(signedDegrees) - Double($0)) < 0.001 }) else { return nil }
        return AudioCue(
            speech: "\(signedDegrees < 0 ? "왼쪽" : "오른쪽") \(magnitude)도",
            frequency: signedDegrees < 0 ? 440 : 880,
            count: magnitude == 30 ? 1 : magnitude == 45 ? 2 : 3,
            pulseDuration: 0.16, gap: 0.12
        )
    }

    static let reset = AudioCue(speech: "기준 방향을 0도로 설정했어요", frequency: 660,
                               count: 1, pulseDuration: 0.5, gap: 0)

    var beepDescription: String { "\(frequency < 660 ? "낮은" : frequency > 660 ? "높은" : "중간") 음 · \(count)회" }
    var duration: Double { Double(count) * pulseDuration + Double(max(0, count - 1)) * gap }

    /// Mono PCM WAV with a short fade on each pulse to avoid clicks. No external sound assets.
    func waveData() -> Data {
        let sampleRate = 44_100
        let frames = Int((duration * Double(sampleRate)).rounded())
        var pcm = Data(capacity: frames * 2)
        for index in 0..<frames {
            let time = Double(index) / Double(sampleRate)
            let withinPulse = time.truncatingRemainder(dividingBy: pulseDuration + gap)
            let envelope = withinPulse < pulseDuration
                ? max(0, min(1, min(withinPulse / 0.008, (pulseDuration - withinPulse) / 0.008))) : 0
            let value = Int16((sin(2 * .pi * frequency * time) * envelope * 0.35 * Double(Int16.max)).rounded())
            pcm.appendLittleEndian(value)
        }
        var data = Data("RIFF".utf8)
        data.appendLittleEndian(UInt32(36 + pcm.count))
        data.append(Data("WAVEfmt ".utf8))
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1)) // PCM
        data.appendLittleEndian(UInt16(1)) // mono
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(sampleRate * 2))
        data.appendLittleEndian(UInt16(2))
        data.appendLittleEndian(UInt16(16))
        data.append(Data("data".utf8))
        data.appendLittleEndian(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
