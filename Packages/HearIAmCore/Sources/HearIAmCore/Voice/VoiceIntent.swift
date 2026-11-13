import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The screen the user is on when they speak. Only what that screen can do is offered to the model (#87).
public enum VoiceScreen: Equatable, Sendable {
    /// Saved stage list; `stageCount` is the number of stages currently read out or shown.
    case stageList(stageCount: Int)
    case modeChoice
    /// Position, checkpoint, wear and departure checks before guidance starts.
    case preparation
    /// `pointCount` is the number of points the user may return to; 0 when returning is not allowed.
    case guidance(pointCount: Int)
    case recovery

    public var actions: [VoiceIntentAction] {
        switch self {
        case .stageList(let count): return (count > 0 ? [.chooseStage] : []) + [.showAllStages, .repeatInstruction, .cancel]
        case .modeChoice: return [.practice, .performance, .repeatInstruction, .back, .cancel]
        case .preparation: return [.next, .pause, .repeatInstruction, .back, .chooseStageAgain, .cancel]
        case .guidance(let count): return [.continueGuidance, .pause, .repeatInstruction] + (count > 0 ? [.returnToPoint] : []) + [.chooseStageAgain, .cancel]
        case .recovery: return [.continueGuidance, .repeatInstruction, .chooseStageAgain, .cancel]
        }
    }

    /// A command of this screen that the words are a sound or two away from (`VoiceCommandParser.near`).
    /// Commands that move the run on (다음, 계속, 무대 다시 선택) are left to the exact list and the model.
    public func nearCommand(_ text: String) -> VoiceCommand? {
        let commands: [VoiceCommand] = actions.compactMap { action in
            switch action {
            case .practice: return .practice
            case .performance: return .performance
            case .pause: return .pause
            case .repeatInstruction: return .repeatInstruction
            case .back: return .back
            case .cancel: return .cancel
            default: return nil
            }
        }
        return VoiceCommandParser.near(text, among: commands)
    }

    var title: String {
        switch self {
        case .stageList(let count): return L("저장된 무대 목록 화면(지금 목록 %@개)", count)
        case .modeChoice: return L("연습용 또는 실전용을 고르는 화면")
        case .preparation: return L("안내 시작 전 위치 · 착용 확인 화면")
        case .guidance(let count): return count > 0 ? L("이동 안내 화면(지점 P1~P%@)", count) : L("이동 안내 화면")
        case .recovery: return L("안내가 끊겨 다시 이어야 하는 화면")
        }
    }
}

/// Everything the model may pick. Each screen offers a subset; the rest are rejected (#87).
public enum VoiceIntentAction: String, CaseIterable, Sendable {
    case continueGuidance, pause, repeatInstruction, next, practice, performance, cancel, returnToPoint, showAllStages, chooseStage, back, chooseStageAgain

    var meaning: String {
        switch self {
        case .continueGuidance: return L("안내를 계속하거나 이어서 하라는 말")
        case .pause: return L("잠깐 멈추거나 기다리라는 말")
        case .repeatInstruction: return L("방금 안내를 다시 말해 달라는 말")
        case .next: return L("다음 단계로 넘어가거나, 확인했거나, 시작하라는 말")
        case .practice: return L("연습용으로 하겠다는 말")
        case .performance: return L("실전용이나 공연용으로 하겠다는 말")
        case .cancel: return L("방금 요청을 취소하거나 아니라는 말")
        case .returnToPoint: return L("몇 번 지점(P1, 피원, 세 번째 자리 등)으로 다시 가자는 말. number에 지점 번호를 넣는다. 받아쓰기가 P를 피 · 비 · 삐 · 키로, 숫자를 원 · 윈 · 일 · 엘(1), 투 · 이(2), 쓰리 · 삼(3), 포 · 사(4), 파이브 · 오(5)처럼 적을 수 있다. 예: 키원 = 1, 비투 = 2. 번호가 분명하지 않으면 sure는 false다")
        case .showAllStages: return L("저장된 무대를 전부 보여 주거나 읽어 달라는 말(다 불러와 줘, 무대 뭐 있어 등)")
        case .chooseStage: return L("목록의 몇 번째 무대를 고르겠다는 말. number에 목록 번호를 넣는다")
        case .back: return L("바로 앞 단계나 이전 선택으로 돌아가자는 말")
        case .chooseStageAgain: return L("지금 무대를 그만두고 다른 무대를 고르겠다는 말(무대 바꿔 줘, 다른 무대로 할래 등)")
        }
    }
}

/// What a free-form utterance most likely meant when the exact phrase list did not match (#87):
/// act on it, ask back first, or ignore it. The choice is always one the current screen offers, so
/// speaking freely never widens what the app may do.
public enum VoiceIntentDecision: Equatable, Sendable {
    case command(VoiceCommand)
    case confirm(VoiceCommand)
    case none

    /// Maps a model guess to a decision. An action the screen does not offer, or a number outside
    /// the screen's points or list, is not a command.
    public static func from(action: String, number: Int, sure: Bool, screen: VoiceScreen) -> VoiceIntentDecision {
        guard let action = VoiceIntentAction(rawValue: action), screen.actions.contains(action) else { return .none }
        let command: VoiceCommand
        switch action {
        case .continueGuidance: command = .continueGuidance
        case .pause: command = .pause
        case .repeatInstruction: command = .repeatInstruction
        case .next: command = .next
        case .practice: command = .practice
        case .performance: command = .performance
        case .cancel: command = .cancel
        case .showAllStages: command = .showAllStages
        case .back: command = .back
        case .chooseStageAgain: command = .chooseStageAgain
        case .returnToPoint:
            guard case .guidance(let count) = screen, number >= 1, number <= count else { return .none }
            command = .returnToPoint(number)
        case .chooseStage:
            guard case .stageList(let count) = screen, number >= 1, number <= count else { return .none }
            command = .chooseStage(number)
        }
        // A guessed point or stage moves the user somewhere, and a misheard number can look certain
        // to the model (「키원」 came back as P3 on 10/28), so those are always asked back.
        if action == .returnToPoint || action == .chooseStage { return .confirm(command) }
        return sure ? .command(command) : .confirm(command)
    }

    /// What is done with a model guess, given the words it was made from. On the phone the model named a
    /// command for almost anything on a screen with few commands: of 98 runs over logged room talk (「그러니까」,
    /// 「헬로」, 「왜 이렇게 들어」) 54 came back as a command (11/13), and changing its instructions moved
    /// that only to 45. So the words themselves must speak for the command: they hold one of its cue words
    /// or sound like one of its phrases (`VoiceCommandParser.soundsLike`, strictly), or the guess is nothing.
    /// With that, a command the model is sure of is acted on when the words sound like its phrases and asked
    /// back otherwise (11/09–10). A stage picked by number is judged by the caller, which knows the names.
    public func checked(heard: String) -> VoiceIntentDecision {
        let command: VoiceCommand
        switch self {
        case .command(let guessed), .confirm(let guessed): command = guessed
        case .none: return self
        }
        if case .chooseStage = command { return self }
        let phrased = VoiceCommandParser.hasPhrases(command)
        guard Self.hasCue(heard, for: command) || (phrased && VoiceCommandParser.soundsLike(heard, command, strict: true)) else { return .none }
        guard case .command = self, !VoiceCommandParser.soundsLike(heard, command) else { return self }
        return .confirm(command)
    }

    /// Whether the words hold a word that belongs to the command: 「넘어」 in 「이제 넘어가자」 for 다음.
    static func hasCue(_ heard: String, for command: VoiceCommand) -> Bool {
        let text = VoiceEnglish.canonical(heard)
        let korean = VoiceStageSearch.normalized(text)
        let english = Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let cues: (korean: [String], english: [String])
        switch command {
        case .next, .start:
            cues = (["다음", "넘어", "완료", "했어", "했습니다", "됐어", "됐습니다", "다했", "다됐", "준비", "시작", "확인", "착용", "찼", "출발", "진행", "끝났"],
                    ["next", "done", "ready", "go", "continue", "start", "finished", "proceed"])
        case .continueGuidance:
            cues = (["계속", "이어", "다시", "가자", "갈게", "가줘", "진행", "재개", "출발", "시작"], ["continue", "resume", "go", "keep", "start", "again", "proceed"])
        case .pause:
            cues = (["멈", "잠깐", "잠시", "기다", "정지", "스톱", "쉬", "세워"], ["stop", "wait", "pause", "hold", "moment", "second"])
        case .repeatInstruction:
            cues = (["다시", "한번더", "한번만", "뭐라", "못들", "반복", "말해", "들려"], ["again", "repeat", "say", "what", "pardon"])
        case .practice: cues = (["연습", "리허설"], ["practice", "rehearsal", "rehearse"])
        case .performance: cues = (["실전", "공연", "본무대"], ["performance", "perform", "live", "real", "show"])
        case .cancel: cues = (["취소", "아니", "됐어", "말고", "하지마", "그만"], ["cancel", "no", "never", "nope", "stop"])
        case .back: cues = (["이전", "뒤로", "돌아", "전단계", "전으로"], ["back", "previous", "before"])
        case .chooseStageAgain:
            cues = (["무대", "공연", "바꿔", "바꾸", "다른", "변경"], ["stage", "performance", "another", "change", "different", "switch"])
        case .returnToPoint:
            if korean.contains(where: \.isNumber) { return true }
            cues = (["지점", "포인트", "번", "자리", "돌아", "다시", "피", "비"], ["point", "back", "return", "p"])
        case .showAllStages:
            cues = (["저장", "무대", "공연", "목록", "리스트", "전체", "전부", "모든", "모두", "보여", "불러", "읽어", "알려", "뭐있", "뭐가있"],
                    ["stage", "stages", "performance", "performances", "show", "list", "saved", "everything", "all"])
        case .chooseStage: return true
        }
        return cues.korean.contains(where: korean.contains) || !english.isDisjoint(with: cues.english)
    }

    /// Model instructions listing only the current screen's actions.
    public static func instructions(for screen: VoiceScreen) -> String {
        let lines = screen.actions.map { "\($0.rawValue): \($0.meaning)" }
        return ([L("너는 시각장애 무용수가 무대에서 쓰는 이동 안내 앱의 음성 명령을 고른다."),
                 L("지금 화면: %@. 사용자가 한 한국어 말을 아래 중 하나로만 고른다.", screen.title)]
            + lines
            + [L("none: 위 어느 것도 아닌 말(잡담, 질문, 노래 가사, 이 화면에서 할 수 없는 일 등)"),
               L("번호가 필요 없으면 number는 0이다. 뜻이 분명하면 sure를 true, 짐작이면 false로 한다. 모르겠으면 none이다.")])
            .joined(separator: "\n")
    }
}

/// Short questions for a guessed command, and the yes or no that answers them (#87).
public enum VoiceIntentCopy {
    public static func question(_ command: VoiceCommand) -> String {
        switch command {
        case .continueGuidance: return L("계속 안내할까요?")
        case .pause: return L("안내를 멈출까요?")
        case .repeatInstruction: return L("방금 안내를 다시 들려드릴까요?")
        case .next: return L("다음으로 넘어갈까요?")
        case .start: return L("안내를 시작할까요?")
        case .practice: return L("연습용으로 할까요?")
        case .performance: return L("실전용으로 할까요?")
        case .cancel: return L("취소할까요?")
        case .returnToPoint(let index): return L("%@번 지점으로 다시 안내할까요?", index)
        case .showAllStages: return L("저장된 무대를 모두 읽어드릴까요?")
        case .chooseStage(let index): return L("%@번 무대를 선택할까요?", index)
        case .back: return L("이전 단계로 돌아갈까요?")
        case .chooseStageAgain: return L("지금 안내를 끝내고 무대를 다시 고를까요?")
        }
    }
    public static var declined: String { L("알겠어요. 하지 않을게요.") }

    /// true for yes, false for no, nil when the answer is neither.
    public static func answer(_ text: String) -> Bool? {
        let compact = VoiceEnglish.canonical(text).lowercased().replacingOccurrences(of: #"[\s.!?。！？,~]"#, with: "", options: .regularExpression)
        if yes.contains(compact) { return true }
        if no.contains(compact) { return false }
        return nil
    }
    private static let yes: Set<String> = ["응", "어", "네", "예", "그래", "그래요", "그래줘", "좋아", "좋아요", "맞아", "맞아요", "해줘", "해주세요", "오케이", "yes", "ok", "okay"]
    private static let no: Set<String> = ["아니", "아니요", "아니야", "아뇨", "싫어", "됐어", "괜찮아", "취소", "no"]
}

public protocol VoiceIntentResolving: Sendable {
    func resolve(_ text: String, screen: VoiceScreen) async -> VoiceIntentDecision
}

#if canImport(FoundationModels)
/// On-device Apple Intelligence model, constrained to the action list by guided generation (#87).
@available(iOS 26.0, macOS 26.0, *)
public struct AppleIntelligenceVoiceIntentResolver: VoiceIntentResolving {
    @Generable
    struct Guess {
        @Guide(description: L("사용자가 한 말과 뜻이 같은 명령. 지금 화면의 명령이 아니면 none"))
        var action: Action
        @Guide(description: L("returnToPoint면 지점 번호, chooseStage면 목록 번호, 아니면 0"))
        var number: Int
        @Guide(description: L("뜻이 분명하면 true, 짐작이면 false"))
        var sure: Bool
    }
    @Generable
    enum Action: String {
        case continueGuidance, pause, repeatInstruction, next, practice, performance, cancel, returnToPoint, showAllStages, chooseStage, back, chooseStageAgain, none
    }

    public init() {}

    public static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public func resolve(_ text: String, screen: VoiceScreen) async -> VoiceIntentDecision {
        guard Self.isAvailable else { return .none }
        do {
            let session = LanguageModelSession(instructions: VoiceIntentDecision.instructions(for: screen))
            let guess = try await session.respond(to: text, generating: Guess.self).content
            return .from(action: guess.action.rawValue, number: guess.number, sure: guess.sure, screen: screen)
        } catch {
            return .none
        }
    }
}
#endif
