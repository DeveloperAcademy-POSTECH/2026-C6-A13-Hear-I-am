import XCTest
@testable import HearIAmCore

final class VoiceHomeCaptionTests: XCTestCase {
    private let greeting = "네, 무엇을 할까요? 무대를 스캔할까요, 저장된 공연으로 연습할까요?"

    func testSpeechBeforeWakeAndEnglishTurnsDoNotBecomeRequestCaptions() {
        var caption = VoiceHomeCaption()
        caption.receivePartial("주변 사람의 대화", isAwake: false, isEnglish: false,
                               overlappingNarration: false, spokenLines: [])
        caption.receivePartial("Hear I am", isAwake: true, isEnglish: true,
                               overlappingNarration: false, spokenLines: [])
        XCTAssertEqual(caption.transcript, "")

        caption.receivePartial("라이온 킹 연습할래", isAwake: true, isEnglish: false,
                               overlappingNarration: false, spokenLines: [])
        caption.receivePartial("Hear I am", isAwake: true, isEnglish: true,
                               overlappingNarration: false, spokenLines: [])
        XCTAssertEqual(caption.transcript, "라이온 킹 연습할래")
    }

    func testOneWordAnswerSurvivesOverlappingNarration() {
        var caption = VoiceHomeCaption()
        caption.receivePartial("연습", isAwake: true, isEnglish: false,
                               overlappingNarration: true, spokenLines: [greeting])
        XCTAssertEqual(caption.transcript, "연습")
    }

    func testLeadingNarrationIsRemovedButTheUsersRequestRemains() {
        var caption = VoiceHomeCaption()
        caption.receivePartial("무엇을 할까요 머지 테스트 무대 선택해 줘", isAwake: true, isEnglish: false,
                               overlappingNarration: true, spokenLines: [greeting])
        XCTAssertEqual(caption.transcript, "머지 테스트 무대 선택해 줘")
    }

    func testWordsAreNotStrippedWhenNarrationDidNotOverlap() {
        var caption = VoiceHomeCaption()
        caption.receivePartial("무엇을 할까요", isAwake: true, isEnglish: false,
                               overlappingNarration: false, spokenLines: [greeting])
        XCTAssertEqual(caption.transcript, "무엇을 할까요")
    }

    func testRevisedPartialReplacesRatherThanAppendsTheEarlierGuess() {
        var caption = VoiceHomeCaption()
        caption.receivePartial("라이온 김", isAwake: true, isEnglish: false,
                               overlappingNarration: false, spokenLines: [])
        caption.receivePartial("라이온 킹 연습할래", isAwake: true, isEnglish: false,
                               overlappingNarration: false, spokenLines: [])
        XCTAssertEqual(caption.transcript, "라이온 킹 연습할래")
    }

    func testEchoOnlyRevisionClearsAnEarlierPartial() {
        var caption = VoiceHomeCaption()
        caption.receivePartial("무엇을", isAwake: true, isEnglish: false,
                               overlappingNarration: true, spokenLines: [greeting])
        caption.receivePartial("네 무엇을 할까요", isAwake: true, isEnglish: false,
                               overlappingNarration: true, spokenLines: [greeting])
        XCTAssertEqual(caption.transcript, "")
    }

    func testActualNarrationAndUserTranscriptRemainSeparate() {
        var caption = VoiceHomeCaption()
        caption.updateNarration(greeting)
        caption.receivePartial("연습", isAwake: true, isEnglish: false,
                               overlappingNarration: true, spokenLines: [greeting])
        XCTAssertEqual(caption.narration, greeting)
        XCTAssertEqual(caption.transcript, "연습")

        caption.updateNarration("공연 관리는 조력자 화면에서 사용할 수 있어요.")
        XCTAssertEqual(caption.narration, "공연 관리는 조력자 화면에서 사용할 수 있어요.")
        XCTAssertEqual(caption.transcript, "연습")
    }

    func testRequestRecoveryAndNewConversationClearTheCorrectCaptions() {
        var caption = VoiceHomeCaption()
        caption.updateNarration(greeting)
        caption.receivePartial("라이온 킹", isAwake: true, isEnglish: false,
                               overlappingNarration: false, spokenLines: [])
        caption.clearRequest()
        XCTAssertEqual(caption.transcript, "")
        XCTAssertEqual(caption.narration, greeting)

        caption.receivePartial("효자아트홀", isAwake: true, isEnglish: false,
                               overlappingNarration: false, spokenLines: [])
        caption.reset()
        XCTAssertEqual(caption, VoiceHomeCaption())
    }
}
