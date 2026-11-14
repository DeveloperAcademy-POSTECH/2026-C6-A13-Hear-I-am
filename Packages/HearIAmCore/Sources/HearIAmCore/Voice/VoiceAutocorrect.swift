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
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        for index in words.indices {
            let previous = index > 0 ? words[index - 1].trimmingCharacters(in: .punctuationCharacters) : ""
            guard let fixed = correctWord(words[index], lexicon: lexicon) ?? (saved.contains(previous) ? afterSaved(words[index]) : nil) else { continue }
            words[index] = fixed
            changed = true
        }
        return changed ? words.joined(separator: " ") : text
    }

    /// After 「저장된」 only 무대 or 공연 is ever said, so a word further off is still taken for the nearer one:
    /// 「저장된 모델 보여줘」 (11/03, 11/08, 11/14) is three letters from 무대, past the one a word allows.
    private static let saved: Set<String> = ["저장된", "저장한"]
    private static func afterSaved(_ raw: String) -> String? {
        let core = raw.trimmingCharacters(in: .punctuationCharacters)
        guard !core.isEmpty, let range = raw.range(of: core), core.allSatisfy(isHangul), !["무대", "공연"].contains(core) else { return nil }
        let stems = [(core, "")] + particles.filter { core.hasSuffix($0) }.map { (String(core.dropLast($0.count)), $0) }
        for (stem, particle) in stems where syllables(stem) == 2 {
            let off = ["무대", "공연"].map { ($0, distance(letters(stem), letters($0))) }.sorted { $0.1 < $1.1 }
            guard off[0].1 <= 3, off[0].1 < off[1].1 else { continue }
            // The particle follows the new word: 모델을 → 무대를, 공원을 → 공연을.
            let pairs = ["을": "를", "이": "가", "은": "는", "과": "와", "으로": "로"]
            let open = off[0].0 == "무대"
            let fixedParticle = open ? (pairs[particle] ?? particle) : (pairs.first { $0.value == particle }?.key ?? particle)
            return raw.replacingCharacters(in: range, with: off[0].0 + fixedParticle)
        }
        return nil
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
    static func letters(_ word: String) -> [Int] {
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
    /// The same letters with a consonant counted alike at the head and the foot of a syllable: the ㅂ that
    /// ends 습 and the ㅂ that begins 병 are one sound moved, as in 「연수병」 for 「연습용」.
    static func sounds(_ word: String) -> [Int] {
        let heads = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"), feet = Array(" ㄱㄲㄱㄴㄴㄴㄷㄹㄹㄹㄹㄹㄹㄹㄹㅁㅂㅂㅅㅆㅇㅈㅊㅋㅌㅍㅎ")
        return letters(word).map { letter in
            switch letter {
            case 1000..<1019: return Int(heads[letter - 1000].unicodeScalars.first!.value)
            case 3001..<3028: return Int(feet[letter - 3000].unicodeScalars.first!.value)
            default: return letter
            }
        }
    }
    /// How far `phrase` is from the closest stretch of `text`, letter by letter: 「연수병」 holds 「연습」
    /// one vowel away. Text around the phrase costs nothing.
    static func distance(of phrase: [Int], within text: [Int]) -> Int {
        guard !phrase.isEmpty else { return 0 }
        guard !text.isEmpty else { return phrase.count }
        var row = Array(repeating: 0, count: text.count + 1)
        for i in 1...phrase.count {
            var previous = row[0]; row[0] = i
            for j in 1...text.count {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (phrase[i - 1] == text[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return row.min() ?? phrase.count
    }
    /// How far two words are from each other, letter by letter.
    static func distance(_ a: [Int], _ b: [Int]) -> Int {
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
