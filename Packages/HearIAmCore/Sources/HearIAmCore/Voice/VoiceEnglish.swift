import Foundation

/// English requests, rewritten as the Korean request that means the same (#183). The command parser, the stage
/// search and the Home requests were all built on Korean words and endings; turning 「open Vampire」 into
/// 「Vampire 열어줘」 before they look at it lets English reach every one of them without a second copy of
/// their rules. Text with no English in it comes back unchanged, so this runs whatever the app's language is.
public enum VoiceEnglish {
    public static func canonical(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) }) else { return text }
        // A request that already carries Korean words (a Korean ending after an English stage name) is left alone.
        guard !text.unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) }) else { return text }
        var request = text.lowercased()
            .replacingOccurrences(of: #"[’']"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[.!?,~]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !request.isEmpty, request.count <= 240 else { return text }
        request = strip(request, #"^(?:please |can you |could you |would you |i want to |i would like to |id like to |lets |hey )+"#)
        request = strip(request, #"(?: please| thanks| thank you| for me| now)+$"#)
        if let whole = wholeRequest(request) { return whole }
        // 「yes, start」: an answer or filler before a request.
        if let match = request.range(of: #"^(?:yes|yeah|yep|ok|okay|sure|so|well|um|uh|alright|all right) "#, options: .regularExpression) {
            let rest = String(request[match.upperBound...])
            if let whole = wholeRequest(rest) ?? shaped(rest) { return whole }
        }
        return shaped(request) ?? text
    }

    private static func strip(_ text: String, _ pattern: String) -> String {
        let stripped = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        return stripped.isEmpty ? text : stripped
    }

    private static func wholeRequest(_ request: String) -> String? {
        let compact = request.replacingOccurrences(of: " ", with: "")
        return whole.first { $0.1.contains(compact) }?.0
    }

    /// Requests that are the whole of what was said. A stage called 「Practice Room」 is still a name: only the
    /// bare words count.
    private static let whole: [(String, Set<String>)] = [
        ("네", ["yes", "yeah", "yep", "yup", "sure", "ok", "okay", "right", "correct", "yesplease", "thatsright", "alright", "allright", "doit", "pleasedo"]),
        ("아니", ["no", "nope", "nah", "nothanks", "dont", "notnow"]),
        ("계속", ["continue", "resume", "keepgoing", "goon", "carryon", "goahead", "continueguidance", "keepguiding"]),
        ("멈춰", ["stop", "pause", "wait", "holdon", "waitaminute", "waitasecond", "onemoment", "hold", "stopguidance", "pauseguidance"]),
        ("다시 말해줘", ["repeat", "repeatthat", "saythatagain", "sayitagain", "again", "onemoretime", "whatwasthat", "pardon", "comeagain", "tellmeagain"]),
        ("다음", ["next", "nextstep", "gonext", "gotonext", "gotothenextstep", "confirm", "confirmed", "done", "imdone", "imwearingit", "wearingit",
                "donewearing", "itson", "ready", "imready", "moveon"]),
        ("시작", ["start", "begin", "go", "letsgo", "startguidance", "startnow", "letsstart", "startguiding", "starttheguidance"]),
        ("연습용", ["practice", "practicemode", "rehearsal", "rehearsalmode", "usepractice", "inpractice"]),
        ("실전용", ["live", "livemode", "performancemode", "liveperformance", "performance", "uselive", "inlive", "golive"]),
        ("취소", ["cancel", "nevermind", "cancelthat", "forgetit", "cancelit"]),
        ("이전", ["back", "goback", "previous", "previousstep", "gobackastep", "gotoprevious", "backonestep", "stepback"]),
        ("무대 다시 선택", ["choosestageagain", "chooseanotherstage", "anotherstage", "differentstage", "adifferentstage", "changestage", "changethestage",
                      "pickanotherstage", "switchstage", "switchstages", "chooseadifferentstage", "useanotherstage", "useadifferentstage"]),
        ("닫기", ["close", "exit", "quit", "closeit", "bye", "goodbye", "end", "endconversation", "closethis", "imdonefornow"]),
        ("전체 무대 보여줘", ["showall", "showallstages", "allstages", "listallstages", "showeverything", "showmeallstages", "whatstagesarethere",
                       "readallstages", "fulllist", "showthefulllist", "showsavedstages", "savedstages", "showmesavedstages", "showmethelist",
                       "showthelist", "liststages", "listthestages", "showstages", "showmestages", "whatdoihave", "showallperformances",
                       "allperformances", "savedperformances", "showsavedperformances", "showmesavedperformances", "showmeallperformances"]),
        ("새 스캔", ["scan", "newscan", "scanastage", "scananewstage", "startascan", "startscan", "startscanning", "newstage", "scanstage",
                  "scanthestage", "scananewone", "anewscan", "scanning", "scannewstage"]),
        ("연습", ["practicewithasavedperformance", "rehearse", "rehearsewithasavedperformance", "savedperformance", "useasavedperformance",
                "practicewithsaved", "asavedperformance", "practicewithasavedone", "rehearsalwithasavedperformance"]),
        ("사전 저장된 공연 보여줘", ["showplans", "savedplans", "performanceplans", "showperformanceplans", "showmetheplans", "showsavedplans"])
    ]

    private static let numbers: [String: Int] = [
        "zero": 0, "one": 1, "won": 1, "two": 2, "to": 2, "too": 2, "three": 3, "four": 4, "for": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "ate": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20]
    private static let ordinals: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10]
    private static func number(_ word: String) -> Int? { Int(word) ?? numbers[word] ?? ordinals[word] }
    private static var numberWords: String { (numbers.keys + ["[0-9]{1,3}"]).sorted { $0.count > $1.count }.joined(separator: "|") }
    private static var ordinalWords: String { ordinals.keys.sorted().joined(separator: "|") }

    /// Requests with a name or a number inside them.
    private static func shaped(_ request: String) -> String? {
        // A route point: 「go back to P2」, 「point three」, 「take me to the second point」. Dictation writes P as
        // pee, pea, be or bee.
        let go = #"(?:(?:go|take me|guide me|bring me|return|get me|head|move)(?: back)?(?: to)? |back to |again to )?"#
        if let found = groups(request, "^\(go)(?:the )?(?:p|point|pee|pea|be|bee|spot) ?(?:number )?(\(numberWords))(?: again)?$"), let n = number(found[0]) {
            return "P\(n)로 돌아가"
        }
        if let found = groups(request, "^\(go)(?:the )?(\(ordinalWords)) (?:point|spot)(?: again)?$"), let n = number(found[0]) {
            return "P\(n)로 돌아가"
        }
        // An item of the list on screen: 「number two」, 「the second one」, 「stage 3」, 「2」.
        // Said bare, 「to」 and 「for」 are just words; they are numbers only after 「number」 or 「stage」.
        if let found = groups(request, "^(?:(?:choose|select|pick|open|use) )?(?:number|no|stage|item|performance) (\(numberWords))$"), let n = number(found[0]), n >= 1 {
            return "\(n)번"
        }
        if let found = groups(request, "^(?:(?:choose|select|pick|open|use) )?([0-9]{1,3}|one|two|three|four|five|six|seven|eight|nine|ten)$"), let n = number(found[0]), n >= 1 {
            return "\(n)번"
        }
        if let found = groups(request, "^(?:(?:choose|select|pick|open|use) )?(?:the )?(\(ordinalWords))(?: one| stage| performance| item)?$"), let n = number(found[0]) {
            return "\(n)번"
        }
        // The mode said with the stage: 「Vampire in practice mode」, 「practice with Vampire」.
        if let found = groups(request, #"^(.+?) (?:in |for |with |on |as )?(practice|rehearsal|live)(?: mode)?$"#) ?? groups(request, #"^(.+?) (?:in |for |with |on |as )?(performance) mode$"#) {
            return "\(named(found[0])) \(found[1] == "practice" || found[1] == "rehearsal" ? "연습용" : "실전용")"
        }
        if let found = groups(request, #"^(practice|rehearse|rehearsal|live)(?: mode)? (?:with|for|on|at|in) (.+)$"#) {
            return "\(named(found[1])) \(found[0] == "live" ? "실전용" : "연습용")"
        }
        // A search: 「find stages related to the hall」, 「search for studio」, 「stages at Hyoja Art Hall」.
        let things = #"(?:the )?(?:saved )?(?:stages?|performances?|shows?|lists?)"#
        if let found = groups(request, "^(?:find|search(?: for)?|look for|show(?: me)?|list|get) \(things) (?:related to|about|for|at|in|from|with|of|saved at|saved in) (.+)$") {
            return "\(found[0]) 관련 무대 찾아줘"
        }
        if let found = groups(request, "^\(things) (?:related to|about|at|in|from|saved at|saved in) (.+)$") {
            return "\(found[0]) 관련 무대 찾아줘"
        }
        if let found = groups(request, #"^(?:find|search(?: for)?|look for|look up) (?:the )?(.+?)(?: stages?| performances?)?$"#) {
            return "\(found[0]) 찾아줘"
        }
        // A stage by name: 「open Vampire」, 「use the main hall stage」.
        if let found = groups(request, #"^(?:open|use|select|choose|pick|load|play|go with|start with|start|lets do|run|show(?: me)?) (.+)$"#) {
            return "\(named(found[0])) 열어줘"
        }
        return nil
    }

    /// A name without the article before it or the word 「stage」 after it.
    private static func named(_ text: String) -> String {
        var name = text.replacingOccurrences(of: #"^(?:the |a |an |my )"#, with: "", options: .regularExpression)
        let bare = name.replacingOccurrences(of: #" (?:stage|performance|show)$"#, with: "", options: .regularExpression)
        if !bare.isEmpty { name = bare }
        return name
    }

    private static func groups(_ text: String, _ pattern: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        var found: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            found.append(String(text[range]))
        }
        return found.isEmpty ? nil : found
    }
}
