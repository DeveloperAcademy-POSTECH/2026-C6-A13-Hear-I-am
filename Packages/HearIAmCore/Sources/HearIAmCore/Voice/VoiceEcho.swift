import Foundation

/// The phone's own narration sometimes comes back through the microphone and is written down as if the
/// user had said it (「공연 찾기. 어떤 …」 heard as 「개 찾기 어떤」, 11/01). These checks compare what was heard
/// with the lines the app is saying or has just said.
public enum VoiceEcho {
    /// Most of the heard words appear in the lines: the app hearing itself.
    /// A single word is never taken for echo: 「연습」 and 「2번」 are the answers the app asks for, and they
    /// appear in its own question or list (dropped as echo on 11/01).
    public static func isEcho(_ heard: String, of lines: [String]) -> Bool {
        let words = words(heard)
        guard words.count > 1 else { return false }
        let spoken = lines.map(VoiceStageSearch.normalized)
        let echoed = words.filter { word in spoken.contains { $0.contains(word) } }.count
        return Double(echoed) / Double(words.count) >= 0.6
    }

    /// Drops the words at the start that the app itself was saying, keeping what the user added after
    /// (「무엇을 머지 테스트 선택해 줘」 → 「머지 테스트 선택해 줘」). Empty when everything was echo.
    public static func strippingLeadingEcho(_ heard: String, of lines: [String]) -> String {
        let spoken = lines.map(VoiceStageSearch.normalized)
        var parts = heard.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count > 1 else { return heard }
        while let first = parts.first {
            let word = VoiceStageSearch.normalized(first)
            guard word.isEmpty || spoken.contains(where: { $0.contains(word) }) else { break }
            parts.removeFirst()
        }
        return parts.joined(separator: " ")
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { VoiceStageSearch.normalized(String($0)) }.filter { !$0.isEmpty }
    }
}
