/// Requests to the voice agent that belong to another tab rather than to guidance. Pre-saved plans
/// (공연 사전 저장) are drawings for reference while scanning, not stages guidance can use. A new scan
/// opens from the 장소 tab; the helper does the scan itself with buttons (10/28).
public enum VoiceAppRequest: Equatable, Sendable {
    case plans
    case scan

    public static func resolve(_ text: String) -> VoiceAppRequest? {
        let compact = text.lowercased().replacingOccurrences(of: #"[\s.!?。！？,~]"#, with: "", options: .regularExpression)
        if planWords.contains(where: compact.contains) { return .plans }
        return scanWords.contains(where: compact.contains) ? .scan : nil
    }
    private static let planWords = ["사전저장", "사전에저장", "미리저장", "미리그린", "미리그려", "그려둔", "그려놓은", "사전도면", "공연도면"]
    /// 「스캔한 무대」 asks for saved stages, so only words that start a scan count.
    private static let scanWords = ["새스캔", "새로스캔", "스캔시작", "스캔해", "스캔할", "스캔하", "스캔열어", "스캔켜", "새무대", "무대새로", "무대만들"]

    /// What the agent says after opening the plans tab: the names, then why they cannot start guidance.
    public static func plansAnswer(names: [String]) -> [String] {
        guard !names.isEmpty else { return ["공연 사전 저장에 저장한 공연이 없어요."] }
        let shown = names.prefix(5).joined(separator: ", ")
        let more = names.count > 5 ? " 외 \(names.count - 5)개" : ""
        return ["공연 사전 저장에 \(names.count)개가 있어요. \(shown)\(more).",
                "사전 저장은 무대를 스캔할 때 참고하는 도면이에요. 안내에 쓰려면 먼저 그 무대를 스캔해야 해요."]
    }

    /// Said before the scan screen opens; that screen stops listening, so this is the last thing heard.
    public static let scanAnswer = ["새 무대 스캔을 열게요. 스캔은 조력자가 화면 버튼으로 진행해요."]
    /// Guidance offers a scan when nothing is saved; 「응」 then opens it.
    public static let noStageOffer = ["저장된 무대가 없어요. 새 무대를 스캔할까요? 스캔은 조력자가 화면 버튼으로 진행해요."]
}
