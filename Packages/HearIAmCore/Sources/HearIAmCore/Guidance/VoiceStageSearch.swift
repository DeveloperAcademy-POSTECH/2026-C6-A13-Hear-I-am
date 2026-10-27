import Foundation

/// Searches saved names only. A keyword match never silently chooses one of several stages.
public enum VoiceStageMatch: Equatable, Sendable {
    case selected(Int)
    case results(query: String, indices: [Int])
    case none
}

public enum VoiceStageSearch {
    public static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ko_KR"))
            .filter { $0.isLetter || $0.isNumber }
    }

    public static func resolve(_ text: String, names: [String], contexts: [[String]] = []) -> VoiceStageMatch {
        let request=normalized(text)
        guard !request.isEmpty, request.count <= 240 else { return .none }
        let names=names.map(normalized)
        let paths=names.indices.map { index in
            contexts.indices.contains(index) ? contexts[index].map(normalized).filter { !$0.isEmpty } : []
        }
        let aliases=names.indices.map { index in
            [names[index]] + paths[index].map {$0+names[index]} + [paths[index].joined()+names[index]]
        }
        let explicitSearch=["관련", "검색", "찾아", "목록", "리스트", "모든무대", "전체무대"].contains { request.contains($0) }
        let endings=["을선택해주세요", "를선택해주세요", "을선택해줘", "를선택해줘", "선택해주세요", "선택해줘", "선택", "사용할게요", "사용할게", "사용하기", "사용", "열어주세요", "열어줘", "로안내해줘"]
        if !explicitSearch {
            let exact=names.indices.filter { index in
                aliases[index].contains { name in
                    !name.isEmpty && (request == name || endings.contains { request == name+$0 })
                }
            }
            if exact.count == 1 { return .selected(exact[0]) }
            if exact.count > 1 { return .results(query: text, indices: exact) }
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
        keyword=keyword.replacingOccurrences(of: #"(?:의)?(?:무대리스트|무대목록|공연목록|공연리스트|무대|공연|목록|리스트)$"#, with: "", options: .regularExpression)
        guard !keyword.isEmpty else { return .none }
        let indices=names.indices.filter { index in (aliases[index]+paths[index]).contains {$0.contains(keyword)} }
        return .results(query: keyword, indices: indices)
    }

    /// A keyword search such as 「강당 관련 무대 찾아줘」. When it finds nothing, the answer is that nothing
    /// matched; it is not handed to the Apple Intelligence model, which might pick a stage anyway (#87).
    public static func isKeywordSearch(_ text: String) -> Bool {
        let request=normalized(text)
        return ["관련", "검색", "찾아"].contains { request.contains($0) }
    }

    /// One-based ordinals always refer to the currently visible result list.
    public static func ordinal(_ text: String) -> Int? {
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
