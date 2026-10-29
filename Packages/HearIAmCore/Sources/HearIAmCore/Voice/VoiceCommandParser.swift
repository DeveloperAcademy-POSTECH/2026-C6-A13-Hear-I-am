import Foundation

/// Deliberately small command vocabulary for the voice rehearsal experiment.
/// Parsing never authorizes movement: the app must still check its phase, fresh pose and saved route.
public enum VoiceCommand: Equatable, Sendable {
    case returnToPoint(Int)
    case continueGuidance, pause, repeatInstruction, next, start, practice, performance, cancel
    /// Reached only through the Apple Intelligence model (#87); exact stage phrases stay in VoiceStageSearch.
    case showAllStages
    case chooseStage(Int)
    /// One step back before guidance starts, like the 「취소 · 이전 선택」 button (Figma 05–13).
    case back
    /// Ends this run and goes back to the stage list, like 「무대 다시 선택」 (Figma 21).
    case chooseStageAgain
}

public enum VoiceCommandParser {
    public static func parse(_ text: String) -> VoiceCommand? {
        if let command=parseExact(text) { return command }
        // 「네 시작」: a yes or filler said before an otherwise exact command (field test 10/28).
        guard let match=text.range(of:#"^\s*(?:네|예|응|어|음|자|그럼|좋아|오케이|ok|okay)[\s,.!~]+"#,options:[.regularExpression,.caseInsensitive]) else { return nil }
        return parseExact(String(text[match.upperBound...]))
    }

    private static func parseExact(_ text: String) -> VoiceCommand? {
        let normalized=text.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"ko_KR"))
            .trimmingCharacters(in:.whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 240 else { return nil }
        let compact=normalized.replacingOccurrences(of:#"[\s.!?。！？,]"#,with:"",options:.regularExpression)
        for (command,phrases) in vocabulary where phrases.contains(compact) { return command }
        return pointCommand(normalized)
    }

    private static let vocabulary: [(VoiceCommand,Set<String>)] = [
        (.continueGuidance,["계속","계속해","계속해줘","계속해주세요","계속진행","계속진행해줘","계속진행해주세요","계속안내해줘","이어서","이어서안내해줘","이어서해주세요","다시시작","재개","continue","resume","keepgoing"]),
        (.pause,["멈춰","멈춰줘","멈춰주세요","잠깐","잠시멈춰","잠시멈춰주세요","잠깐멈춰","잠깐멈춰줘","일시정지","정지","stop","pause"]),
        (.repeatInstruction,["다시말해줘","다시말해주세요","다시들려줘","다시들려주세요","다시듣기","설명다시","설명다시해줘","한번더말해줘","repeat","saythatagain"]),
        (.next,["다음","다음으로","다음단계","다음으로넘어가","다음으로넘어가줘","다음으로넘어가주세요","다음단계로","확인","착용완료","next","nextstep"]),
        (.start,["시작","시작해","시작해줘","시작해주세요","안내시작","안내시작해줘","안내시작해주세요","출발","출발할게","출발할게요","출발해","출발해줘","출발하자","start","startguidance"]),
        (.practice,["연습","연습용","연습모드","연습으로","연습할게","연습할게요","연습용으로","연습용으로할게","연습용으로할게요","practice","rehearsal"]),
        (.performance,["실전","실전용","실전모드","공연","공연용","공연모드","실전으로","실전용으로","실전으로할게","실전용으로할게요","공연용으로","performance","liveperformance"]),
        (.cancel,["취소","취소해","취소해줘","취소해주세요","아니","아니요","cancel","no"]),
        (.back,["이전","이전으로","이전단계","이전단계로","이전으로가줘","이전으로돌아가","이전으로돌아가줘","이전단계로가줘","이전단계로돌아가","이전단계로돌아가줘","이전으로가","전단계","전단계로","전단계로가줘","뒤로가기","이전선택","back","goback"]),
        (.chooseStageAgain,["무대다시선택","무대다시선택해줘","무대다시선택할래","무대다시고를래","무대다시골라줘","무대다시고르기","다른무대","다른무대로","다른무대선택","다른무대로할래","무대바꿔","무대바꿔줘","무대변경","무대변경해줘"])
    ]

    private struct PointToken { let range: NSRange; let index: Int }
    static let sinoKorean=["일":1,"이":2,"삼":3,"사":4,"오":5,"육":6,"칠":7,"팔":8,"구":9,"십":10]
    private static func pointCommand(_ text: String) -> VoiceCommand? {
        var tokens:[PointToken]=[]
        collect(#"(?<![a-z0-9-])(?:p|point)\s*([0-9]{1,3})(?![0-9])"#,in:text,into:&tokens) { Int($0) }
        // Dictation also hears P as 비 (field test 10/28: 「비 일로 돌아가」).
        collect(#"[피비]\s*([0-9]{1,3})(?![0-9])"#,in:text,into:&tokens) { Int($0) }
        collect(#"(?<![0-9-])([0-9]{1,3})\s*(?:번(?:째)?|지점|포인트)"#,in:text,into:&tokens) { Int($0) }
        // 「2번」 and 「이번」 sound the same; dictation writes the everyday word (field test 10/28).
        collect(#"(?<![가-힣])(일|이|삼|사|오|육|칠|팔|구|십)\s*번(?!째)"#,in:text,into:&tokens) { sinoKorean[$0] }
        let spokenNumbers:[String:Int]=[
            "제로":0,"영":0,"일":1,"원":1,"이":2,"투":2,"삼":3,"쓰리":3,"사":4,"포":4,
            "오":5,"파이브":5,"육":6,"식스":6,"칠":7,"세븐":7,"팔":8,"에잇":8,"구":9,"나인":9,
            "십":10,"텐":10,"십일":11,"십이":12,"십삼":13,"십사":14,"십오":15,"십육":16,
            "십칠":17,"십팔":18,"십구":19,"이십":20]
        let words=spokenNumbers.keys.sorted {$0.count > $1.count}.joined(separator:"|")
        let pointEnd="(?=\\s|$|번|지점|포인트|로|으로|에|까지|부터|말고|아니)"
        collect("[피비]\\s*(\(words))"+pointEnd,in:text,into:&tokens) { spokenNumbers[$0] }
        // Whole-word mishearings of P1 seen in the field: 비일 runs together as 비닐, 피원 as 피엘.
        collect("(?<![가-힣])(비닐|피닐|피엘)"+pointEnd,in:text,into:&tokens) { _ in 1 }
        let englishNumbers=["zero":0,"one":1,"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,"eight":8,"nine":9,"ten":10]
        let englishWords=englishNumbers.keys.sorted().joined(separator:"|")
        collect("\\b(?:p|point)\\s+(\(englishWords))\\b",in:text,into:&tokens) { englishNumbers[$0] }
        let ordinalNumbers=["첫":1,"첫째":1,"한":1,"두":2,"둘":2,"세":3,"셋":3,"네":4,"넷":4,"다섯":5,"여섯":6,"일곱":7,"여덟":8,"아홉":9,"열":10]
        let ordinals=ordinalNumbers.keys.sorted {$0.count > $1.count}.joined(separator:"|")
        collect("(\(ordinals))\\s*번째",in:text,into:&tokens) { ordinalNumbers[$0] }
        // More than one point reference is ambiguous, even if a correction happens to repeat the same ID.
        guard tokens.count == 1, let token=tokens.first, let range=Range(token.range,in:text) else { return nil }
        var request=text
        request.replaceSubrange(range,with:"§")
        let compact=request.replacingOccurrences(of:#"[\s.!?。！？,]"#,with:"",options:.regularExpression)
        let korean = #"^(?:다시)?§(?:번)?(?:지점|포인트)?(?:으로|로|에|까지)?(?:다시)?(?:안내(?:해줘|해주세요|해줄래|해줄래요)?|돌아가(?:줘|주세요|자)?|들어가(?:줘|주세요)?|가(?:줘|주세요|자)?|이동(?:해줘|해주세요)?|데려다(?:줘|주세요))?$"#
        let english = #"^(?:(?:please)?(?:takemebackto|takemeto|gobackto|goto|returnto))?§(?:please)?$"#
        guard compact.range(of:korean,options:.regularExpression) != nil || compact.range(of:english,options:.regularExpression) != nil else { return nil }
        return .returnToPoint(token.index)
    }

    private static func collect(_ pattern: String,in text: String,into tokens: inout [PointToken],decode: (String)->Int?) {
        guard let expression=try? NSRegularExpression(pattern:pattern) else { return }
        for match in expression.matches(in:text,range:NSRange(text.startIndex...,in:text)) {
            guard let numberRange=Range(match.range(at:1),in:text),let index=decode(String(text[numberRange])) else { continue }
            // Numeric forms such as P2번 can overlap; keep the more explicit P token.
            guard !tokens.contains(where:{NSIntersectionRange($0.range,match.range).length > 0}) else { continue }
            tokens.append(PointToken(range:match.range,index:index))
        }
    }
}
