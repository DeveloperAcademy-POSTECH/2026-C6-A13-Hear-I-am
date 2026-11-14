import Foundation

/// Words that ask the app for nothing: someone talking nearby, a song, a scrap of the app's own voice (#203).
/// While the conversation is open everything heard is taken as a request, and such words were answered with
/// the long 「요청을 확실히 이해하지 못했어요」, which kept the conversation open for the next scrap of talk
/// (11/13, more than twenty times in a row). They hold no word of any command, no number, no yes or no and
/// no name on offer; the model's answer for them is dropped anyway (`VoiceIntentDecision.checked`), so
/// nothing is lost by passing them over without a word.
///
/// A yes or no counts only when the app has asked something (`expectsAnswer`): 「Okay okay」 and 「Yeah yeah」
/// from people talking nearby, and the app's own 「네」 heard back, came in as a yes to no question.
public enum VoiceChatter {
    public static func isChatter(_ text: String, names: [String] = [], contexts: [[String]] = [], screen: VoiceScreen? = nil,
                                 expectsAnswer: Bool = false) -> Bool {
        if VoiceCommandParser.parse(text) != nil || VoiceCommandParser.isClose(text) { return false }
        if VoiceWakeWord.request(in: text) != nil { return false }
        if VoiceAppRequest.resolve(text) != nil { return false }
        if expectsAnswer, VoiceIntentCopy.answer(text) != nil { return false }
        if screen?.nearCommand(text) != nil { return false }
        if text.contains(where: \.isNumber) || VoiceStageSearch.ordinal(text) != nil { return false }
        if VoiceStageSearch.isKeywordSearch(text) { return false }
        // The same test the model's answer has to pass: a word of the command, or the sound of its phrase
        // (「작용 하래요」 for 착용 했어요, 「연수병」 for 연습용, both acted on through the model on 11/09).
        if commands.contains(where: { VoiceIntentDecision.hasCue(text, for: $0)
            || (VoiceCommandParser.hasPhrases($0) && VoiceCommandParser.soundsLike(text, $0, strict: true)) }) { return false }
        // Picking from the list without a name: 「선택해」, 「마지막」 cut from 「마지막 공연」 (11/01, 11/13).
        let korean = VoiceStageSearch.normalized(VoiceEnglish.canonical(text))
        let english = Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        if picking.korean.contains(where: korean.contains) || !english.isDisjoint(with: picking.english) { return false }
        if !names.isEmpty {
            if VoiceStageSearch.closest(text, names: names) != nil { return false }
            switch VoiceStageSearch.resolve(text, names: names, contexts: contexts) {
            case .selected: return false
            case .results(_, let indices) where !indices.isEmpty: return false
            default: break
            }
        }
        return true
    }

    static let picking = (korean: ["선택", "골라", "고를", "마지막", "처음", "이걸로", "그걸로"], english: ["select", "choose", "pick", "last", "first"])
    static let commands: [VoiceCommand] = [.next, .start, .continueGuidance, .pause, .repeatInstruction, .practice, .performance,
                                           .cancel, .back, .chooseStageAgain, .showAllStages, .returnToPoint(1)]
}
