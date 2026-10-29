import Foundation

/// Rewrites point names that dictation spelled by sound (「삐원」, 「키원」, 「피윈」) as 「P1」 before the
/// Apple Intelligence model reads the request (#90). The on-device model guesses numbers from sound
/// poorly, so the app compares sounds itself, letter by letter (jamo). The model's point choices are
/// still asked back before anything moves.
public enum VoicePointSpelling {
    public static func normalized(_ text: String) -> String {
        let letters = Array(text)
        var output = ""
        var index = 0
        while index < letters.count {
            if isPointPrefix(letters[index]), let (number, length) = number(after: index + 1, in: letters) {
                output += "P\(number)"
                index += 1 + length
            } else {
                output.append(letters[index])
                index += 1
            }
        }
        return output
    }

    private static let numbers: [(String, Int)] = [
        ("원", 1), ("투", 2), ("쓰리", 3), ("포", 4), ("파이브", 5), ("식스", 6), ("세븐", 7), ("에잇", 8), ("나인", 9), ("텐", 10),
        ("일", 1), ("이", 2), ("삼", 3), ("사", 4), ("오", 5), ("육", 6), ("칠", 7), ("팔", 8), ("구", 9), ("십", 10)
    ]

    /// 피 · 비 · 삐 · 키 with no final consonant, and not inside a longer word.
    private static func isPointPrefix(_ letter: Character) -> Bool {
        guard let jamo = jamo(letter), jamo.final == 0, jamo.medial == 20 else { return false }
        return [7, 8, 15, 17].contains(jamo.initial)
    }

    /// The number spelled right after a prefix, allowing one jamo of difference when no spelling matches
    /// exactly. A tie between different numbers is not a point.
    private static func number(after start: Int, in letters: [Character]) -> (Int, Int)? {
        var first = start
        while first < letters.count, letters[first] == " " { first += 1 }
        guard first < letters.count, jamo(letters[first]) != nil else { return nil }
        var best: (distance: Int, number: Int, end: Int)?
        var tie = false
        for length in 1...3 where first + length <= letters.count {
            let candidate = letters[first..<first + length]
            guard candidate.allSatisfy({ jamo($0) != nil }) else { break }
            let sound = candidate.flatMap(sounds)
            for (word, value) in numbers where word.count == length {
                let distance = levenshtein(sound, word.flatMap(sounds))
                guard distance <= 1 else { continue }
                if best == nil || distance < best!.distance || (distance == best!.distance && length > best!.end - first) {
                    best = (distance, value, first + length); tie = false
                } else if distance == best!.distance, length == best!.end - first, value != best!.number {
                    tie = true
                }
            }
        }
        guard let best, !tie, best.end == letters.count || isBoundary(letters[best.end]) else { return nil }
        return (best.number, best.end - start)
    }

    /// What may follow a point name: a space, the end, or a particle such as 로 · 으로 · 에 · 번 · 쪽.
    private static func isBoundary(_ letter: Character) -> Bool {
        letter.isWhitespace || letter.isPunctuation || "로으에까번지쪽말부".contains(letter)
    }

    private static func jamo(_ letter: Character) -> (initial: Int, medial: Int, final: Int)? {
        guard let scalar = letter.unicodeScalars.first, letter.unicodeScalars.count == 1,
              (0xAC00...0xD7A3).contains(scalar.value) else { return nil }
        let index = Int(scalar.value) - 0xAC00
        return (index / 588, (index % 588) / 28, index % 28)
    }

    private static func sounds(_ letter: Character) -> [Int] {
        guard let jamo = jamo(letter) else { return [] }
        return [jamo.initial, 100 + jamo.medial, 200 + jamo.final]
    }

    private static func levenshtein(_ a: [Int], _ b: [Int]) -> Int {
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1]
            for (j, y) in b.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count]
    }
}
