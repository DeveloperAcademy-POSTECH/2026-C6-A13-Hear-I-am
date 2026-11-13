import Foundation

/// Searches saved names only. A keyword match never silently chooses one of several stages.
public enum VoiceStageMatch: Equatable, Sendable {
    case selected(Int)
    case results(query: String, indices: [Int])
    case none
}

public enum VoiceStageSearch {
    public static func normalized(_ text: String) -> String {
        var text = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ko_KR"))
            .filter { $0.isLetter || $0.isNumber }
        // 「확인점 두개」 names the stage 「확인점 2개」 (11/03 device log): counted numbers are written as digits.
        for (word, digit) in countWords { text = text.replacingOccurrences(of: word + "개", with: "\(digit)개") }
        return text
    }
    private static let countWords = [("다섯", 5), ("여섯", 6), ("일곱", 7), ("여덟", 8), ("아홉", 9), ("한", 1), ("두", 2), ("세", 3), ("네", 4), ("열", 10)]

    /// A name as it is said aloud: 「장면1」 is 「장면일」, 「제12장」 is 「제십이장」. Dictation writes the number
    /// as a word (「장면 일 연습용」 found nothing on 11/11), so a name is also known by this form.
    static func spoken(_ name: String) -> String {
        let digits = ["영", "일", "이", "삼", "사", "오", "육", "칠", "팔", "구"]
        var result = "", run = ""
        func flush() {
            guard !run.isEmpty else { return }
            if let number = Int(run), run.count <= 2, !(run.count == 2 && run.hasPrefix("0")) {
                let tens = number / 10, ones = number % 10
                if tens > 0 { result += (tens > 1 ? digits[tens] : "") + "십" }
                if ones > 0 || tens == 0 { result += digits[ones] }
            } else {
                result += run.compactMap { $0.wholeNumberValue }.map { digits[$0] }.joined()
            }
            run = ""
        }
        for character in name {
            if character.isASCII, character.isNumber { run.append(character) } else { flush(); result.append(character) }
        }
        flush()
        return result
    }

    /// The name heard with one sound wrong, as 「확인 좀 2개」 or 「확인점 조개」 for 「확인점 2개」 (11/03).
    /// Only when exactly one name comes that close. Names of four or more letters may be off by one letter,
    /// eight or more by two, ten or more by three (「오늘은 사랑하지 않습니다」 for 「오늘도 출항하지 않습니다」,
    /// 11/11). A three-letter name is too short for that: it counts only when the whole request is that name
    /// with one consonant or vowel changed (「마루 앱」 for 「마루랩」, 11/12).
    static func nearlyNamed(_ request: String, names: [String]) -> Int? {
        var whole = request
        for ending in endings where whole.hasSuffix(ending) && whole.count > ending.count {
            whole = String(whole.dropLast(ending.count)); break
        }
        let close = names.indices.filter { index in
            let name = Array(names[index])
            if name.count == 3 {
                let hangul: (String) -> Bool = { $0.unicodeScalars.allSatisfy { (0xAC00...0xD7A3).contains($0.value) } }
                return whole.count == 3 && hangul(whole) && hangul(names[index])
                    && VoiceAutocorrect.distance(VoiceAutocorrect.letters(whole), VoiceAutocorrect.letters(names[index])) <= 1
            }
            guard name.count >= 4 else { return false }
            let heard = Array(request)
            let allowed = name.count >= 10 ? 3 : name.count >= 8 ? 2 : 1
            for length in max(1, name.count - allowed)...(name.count + allowed) where length <= heard.count {
                for start in 0...(heard.count - length) where distance(Array(heard[start..<start + length]), name) <= allowed {
                    return true
                }
            }
            return false
        }
        let distinct = Set(close.map { names[$0] })
        return distinct.count == 1 && close.count == 1 ? close[0] : nil
    }
    private static let endings=["을선택해주세요", "를선택해주세요", "을선택해줘", "를선택해줘", "선택해주세요", "선택해줘", "선택", "사용할게요", "사용할게", "사용하기", "사용", "열어주세요", "열어줘", "로안내해줘"]
    private static func distance(_ a: [Character], _ b: [Character]) -> Int {
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var previous = row[0]; row[0] = i
            for j in 1...max(b.count, 1) where !b.isEmpty {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return a.isEmpty ? b.count : row[b.count]
    }

    public static func resolve(_ text: String, names: [String], contexts: [[String]] = []) -> VoiceStageMatch {
        let text = VoiceEnglish.canonical(text)
        let request=normalized(text)
        guard !request.isEmpty, request.count <= 240 else { return .none }
        let names=names.map(normalized)
        let paths=names.indices.map { index in
            contexts.indices.contains(index) ? contexts[index].map(normalized).filter { !$0.isEmpty } : []
        }
        let said=names.map(spoken)
        let aliases=names.indices.map { index in
            [names[index], said[index]] + paths[index].map {$0+names[index]} + [paths[index].joined()+names[index]]
        }
        let explicitSearch=["관련", "검색", "찾아", "목록", "리스트", "모든무대", "전체무대"].contains { request.contains($0) }
        if !explicitSearch {
            let exact=names.indices.filter { index in
                aliases[index].contains { name in
                    !name.isEmpty && (request == name || endings.contains { request == name+$0 })
                }
            }
            if exact.count == 1 { return .selected(exact[0]) }
            if exact.count > 1 { return .results(query: text, indices: exact) }
            // A name inside a longer request, as in 「머지테스트 열람」 (11/01). The longest name wins when it
            // holds the shorter ones (「머지테스트」 over 「테스트」); several distinct names make a list.
            let inside=names.indices.filter { names[$0].count >= 2 && (request.contains(names[$0]) || request.contains(said[$0])) }
            if let longest=inside.max(by: { names[$0].count < names[$1].count }) {
                let others=inside.filter { names[$0] != names[longest] }
                if others.allSatisfy({ names[longest].contains(names[$0]) }) {
                    let same=inside.filter { names[$0] == names[longest] }
                    return same.count == 1 ? .selected(longest) : .results(query: text, indices: same)
                }
                return .results(query: text, indices: inside)
            }
            if let near = nearlyNamed(request, names: names) { return .selected(near) }
        }
        if ["전체", "전체목록", "모든무대", "전체무대", "전체무대보여줘", "전체목록보여줘", "모든무대보여줘"].contains(request) {
            return .results(query: "전체", indices: Array(names.indices))
        }
        var keyword=request
        // Remove a related-stage request as a unit before removing general imperative endings.
        let related=#"(?:과|와|에)?(?:관련된|관련있는|관련|관한|대한).*$"#
        keyword=keyword.replacingOccurrences(of: related, with: "", options: .regularExpression)
        let action=#"(?:을|를)?(?:검색해줘|검색해주세요|검색|찾아줘|찾아주세요|보여줘|보여주세요|열어줘|열어주세요|불러줘|불러주세요)$"#
        keyword=keyword.replacingOccurrences(of: action, with: "", options: .regularExpression)
        // 「누리 랩 실행」 names the place and asks to go (11/06 device log): the ask is not part of the name.
        let run=#"(?:으로|로|에서)?(?:실행해줘|실행해주세요|실행할게요|실행할게|실행|진행해줘|진행해주세요|진행)$"#
        keyword=keyword.replacingOccurrences(of: run, with: "", options: .regularExpression)
        keyword=keyword.replacingOccurrences(of: #"(?:의)?(?:무대리스트|무대목록|공연목록|공연리스트|무대|공연|목록|리스트)$"#, with: "", options: .regularExpression)
        // 「효자아트홀에 저장된 공연 리스트 찾아줘」 is the new Home's example (IA 10/29); 「저장된 공연」 alone means all.
        let saved=#"(?:에|에서)?(?:저장된|저장한|저장해둔|저장되어있는|있는)$"#
        if keyword.range(of: saved, options: .regularExpression) != nil {
            keyword=keyword.replacingOccurrences(of: saved, with: "", options: .regularExpression)
            if keyword.isEmpty { return .results(query: "전체", indices: Array(names.indices)) }
        }
        guard !keyword.isEmpty else { return .none }
        let indices=names.indices.filter { index in (aliases[index]+paths[index]).contains {$0.contains(keyword)} }
        // A place said on its own that only one stage belongs to is that stage: 「누리 랩」 under 응가 came
        // back as a list of one and was asked again, twice (11/06 device log). A search asked for as a search
        // (「대연습실 무대 찾아줘」) still answers with the list.
        if indices.count == 1, !explicitSearch { return .selected(indices[0]) }
        return .results(query: keyword, indices: indices)
    }

    /// A keyword search such as 「강당 관련 무대 찾아줘」. When it finds nothing, the answer is that nothing
    /// matched; it is not handed to the Apple Intelligence model, which might pick a stage anyway (#87).
    public static func isKeywordSearch(_ text: String) -> Bool {
        let text = VoiceEnglish.canonical(text)
        let request=normalized(text)
        return ["관련", "검색", "찾아"].contains { request.contains($0) }
    }

    /// Whether a request points at the `number`-th stage by its number or by part of its name. The model
    /// once offered 9번 for 「연남」, which named no stage at all (11/01); such a guess is dropped.
    public static func mentions(_ text: String, number: Int, name: String) -> Bool {
        let text = VoiceEnglish.canonical(text)
        let request=normalized(text), name=normalized(name)
        if request.contains("\(number)") { return true }
        if let sino=VoiceCommandParser.sinoKorean.first(where: { $0.value == number })?.key, request.contains(sino+"번") { return true }
        let ordinals=["첫번째", "두번째", "세번째", "네번째", "다섯번째", "여섯번째", "일곱번째", "여덟번째", "아홉번째", "열번째"]
        if ordinals.indices.contains(number-1), request.contains(ordinals[number-1]) { return true }
        let letters=Array(name)
        guard letters.count >= 2 else { return !name.isEmpty && request.contains(name) }
        return (0..<(letters.count-1)).contains { request.contains(String(letters[$0...$0+1])) }
    }

    /// One-based ordinals always refer to the currently visible result list.
    /// 「3번 무대 스캔」: a number followed by that item's own name picks it, even when several items share
    /// the name (four stages called 「무대 스캔」, 11/03). A name that is not the numbered item's is no pick.
    public static func numbered(_ text: String, names: [String]) -> Int? {
        let text = VoiceEnglish.canonical(text)
        let request = normalized(text)
        let ordinals = ["첫", "두", "세", "네", "다섯", "여섯", "일곱", "여덟", "아홉", "열"]
        var number: Int?, rest = ""
        if let match = request.range(of: #"^[0-9]+번(?:째)?"#, options: .regularExpression) {
            number = Int(request[match].prefix(while: { $0.isNumber })); rest = String(request[match.upperBound...])
        } else if let match = request.range(of: #"^(?:일|이|삼|사|오|육|칠|팔|구|십)번"#, options: .regularExpression) {
            number = VoiceCommandParser.sinoKorean[String(request.prefix(1))]; rest = String(request[match.upperBound...])
        } else if let index = ordinals.firstIndex(where: { request.hasPrefix($0 + "번째") }) {
            number = index + 1; rest = String(request.dropFirst(ordinals[index].count + 2))
        }
        guard let number, names.indices.contains(number - 1) else { return nil }
        for ending in ["을선택해줘", "를선택해줘", "선택해줘", "선택", "으로", "로", "이요", "요"] where rest.hasSuffix(ending) {
            rest = String(rest.dropLast(ending.count)); break
        }
        let name = normalized(names[number - 1])
        return rest.isEmpty || rest == "무대" || rest == "공연" || rest == name || (rest.count >= 2 && name.contains(rest)) ? number : nil
    }

    public static func ordinal(_ text: String) -> Int? {
        let text = VoiceEnglish.canonical(text)
        let request=normalized(text)
        let words=["첫번째", "두번째", "세번째", "네번째", "다섯번째", "여섯번째", "일곱번째", "여덟번째", "아홉번째", "열번째"]
        if let i=words.firstIndex(where: { request == $0 || request == $0+"무대" || request == $0+"선택" || request == $0+"선택해줘" }) { return i+1 }
        // 「2번」 is often written 「이번」: the sounds are the same (field test 10/28).
        if request.range(of: #"^(?:일|이|삼|사|오|육|칠|팔|구|십)번(?:무대|선택|선택해줘)?$"#, options: .regularExpression) != nil {
            return VoiceCommandParser.sinoKorean[String(request.prefix(1))]
        }
        guard request.range(of: #"^[0-9]+번(?:무대|선택|선택해줘)?$"#, options: .regularExpression) != nil else { return nil }
        return Int(request.prefix(while: { $0.isNumber }))
    }
}
