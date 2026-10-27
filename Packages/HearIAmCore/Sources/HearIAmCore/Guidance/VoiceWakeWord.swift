import Foundation

/// The phrase that opens the voice agent from Home (#90). Dictation spells the app name in several
/// ways, so every spelling heard in practice counts as the same call.
public enum VoiceWakeWord {
    public static let phrase = "히얼아이엠"
    /// Hints for the recognizer so it prefers these spellings over ordinary words.
    public static let hints = ["히얼아이엠", "히얼 아이엠", "히어 아이엠", "Hear I am"]

    public static func matches(_ text: String) -> Bool {
        let request = VoiceStageSearch.normalized(text)
        guard !request.isEmpty, request.count <= 240 else { return false }
        return spellings.contains { request.contains($0) }
    }

    /// What was said after the call, or nil when the call is not in `text`. 「히얼아이엠, 멈춰」 gives
    /// 「멈춰」; the call alone gives an empty string.
    public static func request(in text: String) -> String? {
        for spelling in spellings {
            // Dictation may put spaces between any syllables of the name.
            let pattern = spelling.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"\s*"#)
            guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
            return String(text[range.upperBound...]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        }
        return nil
    }

    private static let spellings = [
        "히얼아이엠", "히어아이엠", "히얼아이앰", "히어아이앰", "히얼아이엄", "히어아이엄",
        "히어라이엠", "히얼라이엠", "히아라이엠", "히어라이앰",
        "heariam", "hereiam"
    ]
}
