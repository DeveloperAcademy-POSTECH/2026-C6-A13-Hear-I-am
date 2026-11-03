/// Requests to the voice agent that belong to another tab rather than to guidance. Pre-saved plans
/// (공연 사전 저장) are drawings for reference while scanning, not stages guidance can use. A new scan
/// opens from the 장소 tab; the helper does the scan itself with buttons (10/28).
public enum VoiceAppRequest: Equatable, Sendable {
    case plans
    case scan

    public static func resolve(_ text: String) -> VoiceAppRequest? {
        let compact = compacted(text)
        // 「3번 무대 스캔」 picks the third item of a list whose names hold 「무대 스캔」 (11/03): a number
        // points at something on screen, never at a new scan.
        if compact.range(of: #"[0-9]|(?:첫|두|세|네|다섯|여섯|일곱|여덟|아홉|열)번째|(?:일|이|삼|사|오|육|칠|팔|구|십)번"#, options: .regularExpression) != nil { return nil }
        if planWords.contains(where: compact.contains) { return .plans }
        // The bare answer, said once or twice over (「스캔 스캔」, 11/03 device test).
        if compact.range(of: #"^(?:네|응)?(?:새|새로)?(?:무대)?(?:스캔)+(?:이요|요|할게|할래|할래요|하자|해|해줘|해주세요|하기|시작)?$"#, options: .regularExpression) != nil { return .scan }
        if scanWords.contains(where: compact.contains) { return .scan }
        // Every word sounds like 「스캔」 or goes with it: 「스캔 스캔 스킨」 was 「스캔 스캔」 (11/03 device log).
        let words = text.lowercased().replacingOccurrences(of: #"[.!?。！？,~]"#, with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).map(String.init)
        let scanLike = #"^(?:스캔|스킨|스켄|스캠|스케|스캐|스팸|스펜|스탠|스캣)(?:이요|요|할게|할래|하자|해|해줘|하기|핑)?$"#
        let fits = words.allSatisfy { word in
            word.range(of: scanLike, options: .regularExpression) != nil || ["네", "응", "새", "새로", "무대", "하자", "해줘", "해", "시작"].contains(word)
        }
        // 「스캔」 said alone was written 「스팸」 (11/03); a lone sound-alike counts, as nothing else is asked that way.
        let alone = words.count == 1 && words[0].range(of: scanLike, options: .regularExpression) != nil
        return !words.isEmpty && fits && (alone || words.contains { $0.hasPrefix("스캔") }) ? .scan : nil
    }

    /// Home asks first whether to scan a stage or rehearse with a saved performance (10/31). This is the
    /// rehearse answer: guidance opens on its performance list. Only whole answers count, so a stage or
    /// place name that contains 「연습」(대연습실) is still a name.
    public static func isRehearsal(_ text: String) -> Bool {
        compacted(text).range(of: #"^(?:네|응)?(?:저장된)?(?:공연)?(?:으로)?연습(?:용)?(?:으로)?(?:할게|할래|하기|해|하자|해줘|해주세요|할게요|할래요)?(?:요)?$"#, options: .regularExpression) != nil
    }

    private static func compacted(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: #"[\s.!?。！？,~]"#, with: "", options: .regularExpression)
    }
    private static let planWords = ["사전저장", "사전에저장", "미리저장", "미리그린", "미리그려", "그려둔", "그려놓은", "사전도면", "공연도면"]
    /// 「스캔한 무대」 asks for saved stages, so only words that start a scan count.
    private static let scanWords = ["새스캔", "새로스캔", "스캔시작", "스캔해", "스캔할", "스캔하", "스캔열어", "스캔켜", "새무대", "무대새로", "무대만들", "무대스캔"]

    /// What the agent says when called: the two things it can do.
    public static let homeQuestion = ["네, 무엇을 할까요? 무대를 스캔할까요, 저장된 공연으로 연습할까요?"]

    /// What the agent says after opening the plans tab: the names, then why they cannot start guidance.
    public static func plansAnswer(names: [String]) -> [String] {
        guard !names.isEmpty else { return ["공연 사전 저장에 저장한 공연이 없어요."] }
        let shown = names.prefix(5).joined(separator: ", ")
        let more = names.count > 5 ? " 외 \(names.count - 5)개" : ""
        return ["공연 사전 저장에 \(names.count)개가 있어요. \(shown)\(more).",
                "사전 저장은 무대를 스캔할 때 참고하는 도면이에요. 안내에 쓰려면 먼저 그 무대를 스캔해야 해요."]
    }

    /// Said before the helper's performance management opens.
    public static let plansHandoff = ["공연 관리는 조력자 화면에서 사용할 수 있어요."]
    /// Said before the scan screen opens; that screen stops listening, so this is the last thing heard.
    public static let scanAnswer = ["새 무대 스캔을 열게요. 스캔은 조력자가 화면 버튼으로 진행해요."]
    /// Guidance offers a scan when nothing is saved; 「응」 then opens it.
    public static let noStageOffer = ["저장된 무대가 없어요. 새 무대를 스캔할까요? 스캔은 조력자가 화면 버튼으로 진행해요."]
}
