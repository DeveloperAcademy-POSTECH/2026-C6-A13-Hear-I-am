import Foundation

/// Fixes a misheard word the way a keyboard fixes a typo, using only the words this app expects (11/03:
/// 「저장된 모대 보여줘」 for 「저장된 무대 보여줘」). A word is replaced when it is not one of the app's
/// words and exactly one of them is a sound away: one consonant or vowel, two in words of four syllables
/// or more. Hangul is compared letter by letter (ㅁㅗㄷㅐ against ㅁㅜㄷㅐ), so 모대 is one away from 무대.
/// One-syllable words, numbers and Latin letters are left as heard.
public enum VoiceAutocorrect {
    /// Everyday words of the app's requests that the phrase list does not hold on their own.
    public static let baseWords: [String] = [
        "무대", "공연", "저장된", "저장한", "보여줘", "보여", "불러와", "불러와줘", "찾아줘", "찾아", "스캔", "스캔할래",
        "연습", "연습용", "실전", "실전용", "선택", "선택해줘", "확인점", "목록", "리스트", "관련", "전체", "닫기", "종료",
        "나가기", "다음", "이전", "취소", "시작", "출발", "계속", "멈춰", "다시", "번째", "공연장", "열어줘", "할래", "할게"
    ]
    private static let particles = ["에서", "으로", "을", "를", "이", "가", "은", "는", "로", "에", "의", "도", "와", "과"]

    /// Every whole word of `phrases`, plus the base words, as a lookup set.
    public static func lexicon(_ phrases: [String]) -> Set<String> {
        var words = Set(baseWords)
        for phrase in phrases {
            for word in phrase.split(whereSeparator: \.isWhitespace) { words.insert(String(word)) }
            // A name said without its spaces, as dictation often writes it.
            if phrase.contains(" ") { words.insert(phrase.replacingOccurrences(of: " ", with: "")) }
        }
        return words.filter { syllables($0) >= 2 }
    }

    public static func correct(_ text: String, lexicon: Set<String>) -> String {
        guard !lexicon.isEmpty else { return text }
        var changed = false
        let words = text.split(separator: " ", omittingEmptySubsequences: false).map { piece -> String in
            let word = String(piece)
            guard let fixed = correctWord(word, lexicon: lexicon) else { return word }
            changed = true
            return fixed
        }
        return changed ? words.joined(separator: " ") : text
    }

    static func correctWord(_ raw: String, lexicon: Set<String>) -> String? {
        // Keep punctuation around the word as it was.
        let core = raw.trimmingCharacters(in: .punctuationCharacters)
        guard !core.isEmpty, let range = raw.range(of: core) else { return nil }
        guard core.allSatisfy(isHangul), syllables(core) >= 2, !lexicon.contains(core) else { return nil }
        var fixed = nearest(core, lexicon: lexicon)
        if fixed == nil {
            for particle in particles where core.hasSuffix(particle) {
                let stem = String(core.dropLast(particle.count))
                guard syllables(stem) >= 2, !lexicon.contains(stem) else { continue }
                if let near = nearest(stem, lexicon: lexicon) { fixed = near + particle; break }
            }
        }
        guard let fixed else { return nil }
        return raw.replacingCharacters(in: range, with: fixed)
    }

    private static func nearest(_ word: String, lexicon: Set<String>) -> String? {
        let heard = letters(word), count = syllables(word)
        let allowed = count >= 4 ? 2 : 1
        var best: [String] = [], bestDistance = Int.max
        for candidate in lexicon where syllables(candidate) == count && candidate.allSatisfy(isHangul) {
            let d = distance(heard, letters(candidate))
            guard d <= allowed else { continue }
            if d < bestDistance { bestDistance = d; best = [candidate] } else if d == bestDistance { best.append(candidate) }
        }
        return best.count == 1 ? best[0] : nil
    }

    private static func isHangul(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { (0xAC00...0xD7A3).contains($0.value) }
    }
    private static func syllables(_ word: String) -> Int { word.filter(isHangul).count }

    /// Each syllable as its initial, medial and (when present) final letter.
    private static func letters(_ word: String) -> [Int] {
        var result: [Int] = []
        for scalar in word.unicodeScalars {
            let v = Int(scalar.value)
            guard (0xAC00...0xD7A3).contains(v) else { result.append(v); continue }
            let index = v - 0xAC00
            result.append(1000 + index / 588)
            result.append(2000 + (index % 588) / 28)
            if index % 28 != 0 { result.append(3000 + index % 28) }
        }
        return result
    }
    private static func distance(_ a: [Int], _ b: [Int]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]; row[0] = i
            for j in 1...b.count {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return row[b.count]
    }
}
