/// Room sound the recognizer turns into words: 「.」, 「아.」, 「이 .」, 「그」 (11/02 and 11/03 device tests).
/// Such words were taken as requests; 「이 .」 even reached the intent model and chose 연습용. Fillers at the
/// edges of what was heard are dropped, and what is left must be more than one sound to count.
public enum VoiceNoise {
    /// What was heard without the fillers around it, or nil when nothing of a request is left.
    /// 「이 . 계속」 becomes 「계속」; a lone digit and the one-syllable answers 「네」「응」「예」 stay.
    public static func request(_ text: String) -> String? {
        let cleaned = text.replacingOccurrences(of: #"[.,!?~。！？…·]"#, with: " ", options: .regularExpression)
        var words = cleaned.split(whereSeparator: \.isWhitespace).map(String.init)
        while let first = words.first, fillers.contains(first) { words.removeFirst() }
        while let last = words.last, fillers.contains(last) { words.removeLast() }
        let joined = words.joined(separator: " ")
        guard joined.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        if joined.count == 1, !(joined.first?.isNumber ?? false), !answers.contains(joined) { return nil }
        return joined
    }

    /// Hesitations and the sounds noise most often comes back as.
    static let fillers: Set<String> = ["아", "어", "음", "으", "흠", "엄", "그", "저", "이", "에", "오", "요",
                                       "아요", "이요", "아아", "어어", "음음", "으음", "흐음", "s", "S", "m", "M",
                                       "uh", "um", "umm", "hmm", "hm", "mm", "ah", "oh", "er", "Uh", "Um", "Hmm", "Ah", "Oh"]
    static let answers: Set<String> = ["네", "응", "예"]
}
