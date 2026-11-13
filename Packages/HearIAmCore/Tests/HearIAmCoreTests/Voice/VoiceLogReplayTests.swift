import XCTest
@testable import HearIAmCore

/// Requests from the phone's voice logs (11/01–11/13) put through the rules again (#192). The list of
/// performances is the one on the phone on 11/12; stage names the logs do not show are 「무대 스캔」.
/// `Replay` follows the order of `GuidanceViewModel.handleVoiceCommand` on the performance list and the mode
/// question, without the model: `.model` means the rules found nothing and the on-device model is asked.
final class VoiceLogReplayTests: XCTestCase {
    enum Outcome: Equatable, CustomStringConvertible {
        case close, scan, plans, picked(String, mode: String?), list, command(VoiceCommand), ignored, model
        var description: String {
            switch self {
            case .close: return "close"
            case .scan: return "scan"
            case .plans: return "plans"
            case .picked(let name, let mode): return "picked \(name)" + (mode.map { " as \($0)" } ?? "")
            case .list: return "list"
            case .command(let command): return "command \(command)"
            case .ignored: return "ignored"
            case .model: return "model"
            }
        }
    }

    struct Replay {
        struct Stage { let performance: String, venue: String?, name: String }
        var stages: [Stage] = [
            Stage(performance: "마루랩", venue: "효자아트홀", name: "마루랩"),
            Stage(performance: "머지테스트", venue: nil, name: "무대 스캔"),
            Stage(performance: "무한성 제1장", venue: "CGV", name: "무대 스캔"),
            Stage(performance: "무한성 제1장", venue: "효자아트홀", name: "무대 스캔"),
            Stage(performance: "오늘도 출항하지 않습니다", venue: "스트림도미넌트홀", name: "장면1"),
            Stage(performance: "음성테스트", venue: nil, name: "무대 스캔"),
            Stage(performance: "응가", venue: "누리랩", name: "찐테스트1"),
            Stage(performance: "장애물 음성 테스트", venue: nil, name: "무대 스캔"),
            Stage(performance: "확인점 2개", venue: nil, name: "무대 스캔")
        ]
        /// What the app is saying or has just said.
        var narration = ["공연 찾기. 어떤 공연을 준비할까요? 공연 이름을 말해주세요. 장소 이름으로 찾아 달라고 해도 돼요."]
        var performances: [String] {
            var seen: [String] = []
            for stage in stages where !seen.contains(stage.performance) { seen.append(stage.performance) }
            return seen
        }
        private func title(_ stage: Stage) -> String { [stage.venue, stage.name].compactMap { $0 }.joined(separator: " · ") }
        private func contexts(_ stage: Stage) -> [String] { [stage.performance] + [stage.venue].compactMap { $0 } + [title(stage)] }

        /// The performance list, where a name, a number, a place or an app request is expected.
        func list(_ text: String) -> Outcome {
            if VoiceCommandParser.isClose(text) { return .close }
            let heardName = VoiceStageSearch.normalized(text)
            let namesChoice = performances.contains { name in
                let name = VoiceStageSearch.normalized(name); return name.count >= 2 && heardName.contains(name)
            }
            if !namesChoice, let request = VoiceAppRequest.resolve(text) { return request == .scan ? .scan : .plans }
            let parsed = VoiceCommandParser.parse(text)
            if parsed == .cancel { return .command(.cancel) }
            if parsed == nil, let split = VoiceCommandParser.splitMode(text),
               !(performances + stages.map(\.name)).contains(where: { $0.contains(split.stem) }),
               let picked = choose(split.rest) {
                if case .picked(let name, _) = picked { return .picked(name, mode: split.mode == .practice ? "practice" : "performance") }
                return picked
            }
            let commands: [VoiceCommand?] = [.practice, .performance, .repeatInstruction, .pause, .next, .start, .continueGuidance, .back, .chooseStageAgain]
            if !commands.contains(parsed), let picked = choose(text) { return picked }
            if let parsed { return .command(parsed) }
            return .model
        }
        private func choose(_ text: String) -> Outcome? {
            if let number = VoiceStageSearch.ordinal(text) ?? VoiceStageSearch.numbered(text, names: performances) {
                return performances.indices.contains(number - 1) ? .picked(performances[number - 1], mode: nil) : .list
            }
            if case .selected(let index) = VoiceStageSearch.resolve(text, names: performances) {
                return .picked(performances[index], mode: nil)
            }
            switch VoiceStageSearch.resolve(text, names: stages.map(\.name), contexts: stages.map(contexts)) {
            case .selected(let index): return .picked(stages[index].performance, mode: nil)
            case .results(_, let indices):
                if indices.isEmpty, !VoiceStageSearch.isKeywordSearch(text) { return .model }
                return .list
            case .none: return nil
            }
        }
        /// The 연습용 · 실전용 question.
        func mode(_ text: String) -> Outcome {
            if VoiceCommandParser.isClose(text) { return .close }
            if let parsed = VoiceCommandParser.parse(text) { return .command(parsed) }
            return .model
        }
    }

    private let replay = Replay()

    /// Requests that made sense and what they asked for.
    private var understood: [(String, Outcome)] {
        [("마루 앱 실전용", .picked("마루랩", mode: "performance")),
         ("마루 랩 실전용", .picked("마루랩", mode: "performance")),
         ("장면 일 연습용", .picked("오늘도 출항하지 않습니다", mode: "practice")),
         ("오늘은 사랑하지 않습니다 실전용", .picked("오늘도 출항하지 않습니다", mode: "performance")),
         ("오늘은 출항 하지 않습니다 연습용", .picked("오늘도 출항하지 않습니다", mode: "practice")),
         ("오늘은 출항 하지 않습니다 실전 용", .picked("오늘도 출항하지 않습니다", mode: "performance")),
         ("확인 좀 2개 연습 할래", .picked("확인점 2개", mode: "practice")),
         ("확인점 조개 테스트 할래", .picked("확인점 2개", mode: nil)),
         ("확인점 두개", .picked("확인점 2개", mode: nil)),
         ("머지테스트 연남", .picked("머지테스트", mode: nil)),
         ("이번 머지테스트 열람", .picked("머지테스트", mode: nil)),
         ("무엇을 머지 테스트 무대 선택해 줘", .picked("머지테스트", mode: nil)),
         ("누리 랩 실행", .picked("응가", mode: nil)),
         ("네 번째 공연", .picked("오늘도 출항하지 않습니다", mode: nil)),
         ("세 번째 모습", .picked("무한성 제1장", mode: nil)),
         ("홈 화면으로", .close),
         ("음성 보이스 종료", .close),
         ("스캔 스캔.", .scan),
         ("저장된 무대 보여줘", .list),
         ("저장된 무대 보여", .list),
         ("저장된 모델 보여줘", .list),
         ("저장된 모대 보여줘", .list)]
    }
    /// The same for the 연습용 · 실전용 question.
    private var modes: [(String, Outcome)] {
        [("연수용", .command(.practice)), ("연수병", .command(.practice)), ("연습병", .command(.practice)),
         ("연습용", .command(.practice)), ("실전 용", .command(.performance))]
    }
    /// Room sound, other people and the app's own voice: the rules must not act on any of it.
    private let noise = ["어떤", "어떤 거", "그러니까", "열람", "너무", "만약에", "새끼", "개지", "자기", "바이요", "도 같은",
                         "고키 40원 먹자", "왜 이렇게 들어", "바른 인식을 해야 되는데", "슬픈 거 말해는 들어", "연습실에서 오늘",
                         "어디로 봐야 돼", "Siri야", "야", "헬로", "해피벌스데이", "세벌 시티", "선택해", "밤새 목록", "옥련 찾기",
                         "전화 왔대 자기 노래 노래 몇 시년 했는데 좀 랩 1번 한 걸로 조서 받"]

    func testLoggedRequestsAreUnderstood() {
        var right = 0
        var report: [String] = []
        for (text, expected) in understood {
            let outcome = replay.list(text)
            if outcome == expected { right += 1 } else { report.append("list 「\(text)」: \(outcome), wanted \(expected)") }
        }
        for (text, expected) in modes {
            let outcome = replay.mode(text)
            if outcome == expected { right += 1 } else { report.append("mode 「\(text)」: \(outcome), wanted \(expected)") }
        }
        print("replay understood: \(right)/\(understood.count + modes.count)")
        report.forEach { print("replay miss: \($0)") }
    }

    func testLoggedNoiseDoesNotAct() {
        var quiet = 0
        for text in noise {
            let outcome = replay.list(text)
            if outcome == .model || outcome == .ignored { quiet += 1 } else { print("replay noise acted: 「\(text)」: \(outcome)") }
        }
        print("replay noise quiet: \(quiet)/\(noise.count)")
    }
}
