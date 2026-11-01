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

    var title: String {
        switch self {
        case .stageList(let count): return "저장된 무대 목록 화면(지금 목록 \(count)개)"
        case .modeChoice: return "연습용 또는 실전용을 고르는 화면"
        case .preparation: return "안내 시작 전 위치 · 착용 확인 화면"
        case .guidance(let count): return count > 0 ? "이동 안내 화면(지점 P1~P\(count))" : "이동 안내 화면"
        case .recovery: return "안내가 끊겨 다시 이어야 하는 화면"
        }
    }
}

/// Everything the model may pick. Each screen offers a subset; the rest are rejected (#87).
public enum VoiceIntentAction: String, CaseIterable, Sendable {
    case continueGuidance, pause, repeatInstruction, next, practice, performance, cancel, returnToPoint, showAllStages, chooseStage, back, chooseStageAgain

    var meaning: String {
        switch self {
        case .continueGuidance: return "안내를 계속하거나 이어서 하라는 말"
        case .pause: return "잠깐 멈추거나 기다리라는 말"
        case .repeatInstruction: return "방금 안내를 다시 말해 달라는 말"
        case .next: return "다음 단계로 넘어가거나, 확인했거나, 시작하라는 말"
        case .practice: return "연습용으로 하겠다는 말"
        case .performance: return "실전용이나 공연용으로 하겠다는 말"
        case .cancel: return "방금 요청을 취소하거나 아니라는 말"
        case .returnToPoint: return "몇 번 지점(P1, 피원, 세 번째 자리 등)으로 다시 가자는 말. number에 지점 번호를 넣는다. 받아쓰기가 P를 피 · 비 · 삐 · 키로, 숫자를 원 · 윈 · 일 · 엘(1), 투 · 이(2), 쓰리 · 삼(3), 포 · 사(4), 파이브 · 오(5)처럼 적을 수 있다. 예: 키원 = 1, 비투 = 2. 번호가 분명하지 않으면 sure는 false다"
        case .showAllStages: return "저장된 무대를 전부 보여 주거나 읽어 달라는 말(다 불러와 줘, 무대 뭐 있어 등)"
        case .chooseStage: return "목록의 몇 번째 무대를 고르겠다는 말. number에 목록 번호를 넣는다"
        case .back: return "바로 앞 단계나 이전 선택으로 돌아가자는 말"
        case .chooseStageAgain: return "지금 무대를 그만두고 다른 무대를 고르겠다는 말(무대 바꿔 줘, 다른 무대로 할래 등)"
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

    /// Model instructions listing only the current screen's actions.
    public static func instructions(for screen: VoiceScreen) -> String {
        let lines = screen.actions.map { "\($0.rawValue): \($0.meaning)" }
        return (["너는 시각장애 무용수가 무대에서 쓰는 이동 안내 앱의 음성 명령을 고른다.",
                 "지금 화면: \(screen.title). 사용자가 한 한국어 말을 아래 중 하나로만 고른다."]
            + lines
            + ["none: 위 어느 것도 아닌 말(잡담, 질문, 노래 가사, 이 화면에서 할 수 없는 일 등)",
               "번호가 필요 없으면 number는 0이다. 뜻이 분명하면 sure를 true, 짐작이면 false로 한다. 모르겠으면 none이다."])
            .joined(separator: "\n")
    }
}

/// Short questions for a guessed command, and the yes or no that answers them (#87).
public enum VoiceIntentCopy {
    public static func question(_ command: VoiceCommand) -> String {
        switch command {
        case .continueGuidance: return "계속 안내할까요?"
        case .pause: return "안내를 멈출까요?"
        case .repeatInstruction: return "방금 안내를 다시 들려드릴까요?"
        case .next: return "다음으로 넘어갈까요?"
        case .start: return "안내를 시작할까요?"
        case .practice: return "연습용으로 할까요?"
        case .performance: return "실전용으로 할까요?"
        case .cancel: return "취소할까요?"
        case .returnToPoint(let index): return "\(index)번 지점으로 다시 안내할까요?"
        case .showAllStages: return "저장된 무대를 모두 읽어드릴까요?"
        case .chooseStage(let index): return "\(index)번 무대를 선택할까요?"
        case .back: return "이전 단계로 돌아갈까요?"
        case .chooseStageAgain: return "지금 안내를 끝내고 무대를 다시 고를까요?"
        }
    }
    public static let declined = "알겠어요. 하지 않을게요."

    /// true for yes, false for no, nil when the answer is neither.
    public static func answer(_ text: String) -> Bool? {
        let compact = text.lowercased().replacingOccurrences(of: #"[\s.!?。！？,~]"#, with: "", options: .regularExpression)
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
        @Guide(description: "사용자가 한 말과 뜻이 같은 명령. 지금 화면의 명령이 아니면 none")
        var action: Action
        @Guide(description: "returnToPoint면 지점 번호, chooseStage면 목록 번호, 아니면 0")
        var number: Int
        @Guide(description: "뜻이 분명하면 true, 짐작이면 false")
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
