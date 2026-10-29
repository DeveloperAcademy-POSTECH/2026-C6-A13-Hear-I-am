import XCTest
@testable import HearIAmCore

final class VoiceStepCopyTests: XCTestCase {
    /// Each step opens with the screen's title, then says the word that moves on.
    func testStepsStartWithTheirTitleAndNameTheWordToSay() {
        XCTAssertTrue(VoiceStepCopy.stageList.hasPrefix("무대 선택."))
        XCTAssertTrue(VoiceStepCopy.stageChosen("의자 테스트")[1].hasPrefix("사용 방식 선택."))
        XCTAssertTrue(VoiceStepCopy.restoring.hasPrefix("현장 확인."))
        XCTAssertEqual(VoiceStepCopy.wear[1], "허리띠 착용.")
        XCTAssertTrue(VoiceStepCopy.wear.last!.contains("‘착용 완료’"))
        XCTAssertEqual(VoiceStepCopy.departure(started: false).first, "출발 준비.")
        XCTAssertTrue(VoiceStepCopy.departureReady(started: false, performance: false)[0].contains("‘시작’"))
        XCTAssertTrue(VoiceStepCopy.paused.contains("‘계속’"))
    }
    func testCheckpointsNameTheOneToAimAt() {
        XCTAssertEqual(VoiceStepCopy.checkpoint(1), ["공연장을 찾았어요.", "확인점 1번. 저장한 확인점 1번에 조준점을 맞추고 ‘다음’이라고 말해주세요."])
        XCTAssertEqual(VoiceStepCopy.checkpoint(2)[0], "확인점 1번을 확인했어요.")
        XCTAssertTrue(VoiceStepCopy.checkpoint(2)[1].hasPrefix("확인점 2번."))
    }
    /// Performance mode closes the microphone at the start, so it does not ask for the call.
    func testDepartureReadyTellsHowToSpeakDuringGuidance() {
        XCTAssertTrue(VoiceStepCopy.departureReady(started: false, performance: false)[1].contains("히얼아이엠"))
        XCTAssertTrue(VoiceStepCopy.departureReady(started: false, performance: true)[1].contains("마이크가 꺼져요"))
        XCTAssertEqual(VoiceStepCopy.departureReady(started: true, performance: false), ["재개 준비가 됐어요. ‘계속’이라고 말하면 이어서 안내해요."])
    }
    func testRecoveryLinesSayWhatToSay() {
        XCTAssertTrue(VoiceStepCopy.autoPaused("동선을 벗어났어요.").contains("동선을 벗어났어요. 동선 위로"))
        XCTAssertTrue(VoiceStepCopy.failed("확인점이 맞지 않아요.").contains("‘무대 다시 선택’"))
        XCTAssertTrue(VoiceStepCopy.interrupted.contains("‘계속’"))
    }
}
