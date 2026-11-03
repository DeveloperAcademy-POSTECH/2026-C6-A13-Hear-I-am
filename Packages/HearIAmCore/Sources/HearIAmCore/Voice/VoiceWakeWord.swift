import Foundation

/// The phrase that opens the voice agent from Home (#90). Dictation spells the app name in several
/// ways, so every spelling heard in practice counts as the same call.
public enum VoiceWakeWord {
    /// The app's name, said in English (10/28): an English recognizer writes it as 「Here I am」 every time,
    /// the Korean one only about half the time.
    public static let phrase = "HearIam"
    /// Hints for the recognizer so it prefers these spellings over ordinary words.
    public static let hints = ["Hear I am", "Here I am", "히얼아이엠", "히어 아이엠"]

    public static func matches(_ text: String) -> Bool {
        let request = VoiceStageSearch.normalized(text)
        guard !request.isEmpty, request.count <= 240 else { return false }
        return spellings.contains { request.contains($0) } || wholeCalls.contains(request)
    }

    /// How many times the call appears, for a transcript that keeps growing.
    public static func occurrences(in text: String) -> Int {
        var rest = VoiceStageSearch.normalized(text), count = 0
        while let range = spellings.compactMap({ rest.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) {
            count += 1
            rest = String(rest[range.upperBound...])
        }
        return count
    }

    /// What was said after the call, or nil when the call is not in `text`. 「히얼아이엠, 멈춰」 gives
    /// 「멈춰」; the call alone gives an empty string.
    public static func request(in text: String) -> String? {
        if wholeCalls.contains(VoiceStageSearch.normalized(text)) { return "" }
        for spelling in spellings {
            // Dictation may put spaces between any syllables of the name.
            let pattern = spelling.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"[\s'’]*"#)
            guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
            return String(text[range.upperBound...]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        }
        return nil
    }

    /// Short hearings of the call that are ordinary English inside a sentence, so they count only when
    /// they are all that was heard. Every 「I am」 on 11/03 was a missed call said again seconds later.
    private static let wholeCalls: Set<String> = ["iam", "im", "italian", "hiiam", "yeahiam", "yeiam", "ariam", "heyiam", "herim", "hearme"]

    private static let spellings = [
        "히얼아이엠", "히어아이엠", "히얼아이앰", "히어아이앰", "히얼아이엄", "히어아이엄",
        "히어라이엠", "히얼라이엠", "히아라이엠", "히어라이앰",
        "heariam", "hereiam", "heareyam", "hereyam", "heariim", "hearim", "hereim", "neariam", "beariam", "sureiam",
        // Dictation mixes scripts: 「히어 I am」 (SpeechTranscriber, 10/28).
        "히어iam", "히얼iam", "히어아이am"
    ]
}
