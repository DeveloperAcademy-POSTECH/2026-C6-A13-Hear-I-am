import XCTest
@testable import HearIAmCore

/// Stage and mode in one breath, and model guesses checked against the heard words (#174, 11/09–10 device logs).
final class VoiceCompoundRequestTests: XCTestCase {
    func testModeIsSplitFromTheStage() {
        let cases: [(String, VoiceCommand, String)] = [
            ("뱀파이어 연습용", .practice, "뱀파이어"),
            ("뱀파이어 실전용", .performance, "뱀파이어"),
            ("김이안 연습용으로 열어줘", .practice, "김이안"),
            ("김이안 실전용으로 열어줘", .performance, "김이안"),
            ("소말리아 해적선 연습용으로 열어줘", .practice, "소말리아 해적선"),
            ("연습용으로 뱀파이어 열어줘", .practice, "뱀파이어 열어줘"),
            ("뱀파이어 연습 모드", .practice, "뱀파이어"),
            ("뱀파이어연습용", .practice, "뱀파이어"),
            ("뱀파이어 공연용으로 할게", .performance, "뱀파이어"),
            ("뱀파이어 연습할게", .practice, "뱀파이어"),
        ]
        for (text, mode, rest) in cases {
            let split = VoiceCommandParser.splitMode(text)
            XCTAssertEqual(split?.mode, mode, text)
            XCTAssertEqual(split?.rest, rest, text)
        }
    }

    func testNoModeWithoutAStageOrWithinAWord() {
        // A bare mode is the parser's job; 연습장 is a place and 공연 alone is an everyday word.
        for text in ["연습용", "실전용으로 할게", "작은 연습장", "뱀파이어 공연", "공연 찾기", "저장된 무대 보여줘", "뱀파이어 연습용 실전용"] {
            XCTAssertNil(VoiceCommandParser.splitMode(text), text)
        }
    }

    func testModelGuessesNeedWordsThatSoundLikeTheCommand() {
        let acted: [(String, VoiceCommand)] = [
            ("연수병", .practice), ("연수용", .practice), ("실전용으로 해 줄래", .performance),
            ("다음 단계로 가 주세요", .next), ("계속 안내해 줄래", .continueGuidance), ("잠깐만 멈춰 볼래", .pause),
        ]
        for (text, command) in acted {
            XCTAssertEqual(VoiceIntentDecision.command(command).checked(heard: text), .command(command), text)
        }
        // These were asked back until #192. On the phone the question came for more than half of all room
        // talk (11/13), so words that say nothing of the command are now dropped without a question.
        let dropped: [(String, VoiceCommand)] = [
            ("Siri야", .practice), ("NC병", .practice), ("헬로", .next), ("세벌 시티", .next), ("해피벌스데이", .next), ("사랑", .cancel),
        ]
        for (text, command) in dropped {
            XCTAssertEqual(VoiceIntentDecision.command(command).checked(heard: text), VoiceIntentDecision.none, text)
        }
        XCTAssertEqual(VoiceIntentDecision.confirm(.next).checked(heard: "헬로"), VoiceIntentDecision.none)
        // A request in other words is still asked back, and one with a word about the list is read out.
        XCTAssertEqual(VoiceIntentDecision.command(.next).checked(heard: "이제 넘어가자"), .confirm(.next))
        XCTAssertEqual(VoiceIntentDecision.command(.showAllStages).checked(heard: "무대 뭐 있어"), .command(.showAllStages))
    }

    func testMisheardWearDoneIsNext() {
        for text in ["작용 완료", "작용완료", "착용 완료", "착용했어요"] {
            XCTAssertEqual(VoiceCommandParser.parse(text), .next, text)
        }
    }
}
