import XCTest
@testable import HearIAmCore

final class VoiceEchoTests: XCTestCase {
    let prompt = "공연 찾기. 어떤 공연을 준비할까요? 공연 이름이나 번호를 말해주세요."
    let greeting = "네, 무엇을 할까요? 무대를 스캔할까요, 저장된 공연으로 연습할까요?"

    /// Heard on the 16 Pro Max on 11/01 while the app was speaking.
    func testOwnNarrationIsEcho() {
        XCTAssertTrue(VoiceEcho.isEcho("개 찾기 어떤", of: [prompt]))
        XCTAssertTrue(VoiceEcho.isEcho("네 어떤 거", of: ["네, 어떤 공연을 준비할까요?"]))
        XCTAssertTrue(VoiceEcho.isEcho("무엇을 할까요", of: [greeting]))
    }
    /// What the user says over a list is not in the line being read.
    func testUserWordsOverAListAreNotEcho() {
        XCTAssertFalse(VoiceEcho.isEcho("2번", of: ["1번, Lion King. 효자아트홀.", "전체 관련 무대는 3개예요."]))
        XCTAssertFalse(VoiceEcho.isEcho("오늘을 노래하다", of: ["1번, Lion King. 효자아트홀."]))
        XCTAssertFalse(VoiceEcho.isEcho("", of: [prompt]))
    }
    /// 「연습」 after the greeting and 「2번」 over the list were dropped as echo on 11/01.
    func testOneWordAnswerIsNeverEcho() {
        XCTAssertFalse(VoiceEcho.isEcho("연습", of: [greeting]))
        XCTAssertFalse(VoiceEcho.isEcho("2번", of: ["2번, 테스트2.", "1번, 무대 스캔."]))
        XCTAssertTrue(VoiceEcho.isEcho("2번 테스트2", of: ["2번, 테스트2."]))
    }
    func testLeadingEchoIsStripped() {
        XCTAssertEqual(VoiceEcho.strippingLeadingEcho("무엇을 할까요 머지 테스트 무대 선택해 줘", of: [greeting]), "머지 테스트 무대 선택해 줘")
        // One word the question also holds is the user's own (11/03).
        let home = "네, 무엇을 할까요? 무대를 스캔할까요, 저장된 공연으로 연습할까요?"
        XCTAssertEqual(VoiceEcho.strippingLeadingEcho("저장된 무대 보여줘", of: [home]), "저장된 무대 보여줘")
        XCTAssertEqual(VoiceEcho.strippingLeadingEcho("저장된 공연으로 머지 테스트", of: [home]), "머지 테스트")
        XCTAssertEqual(VoiceEcho.strippingLeadingEcho("네 무엇을 할까요", of: [greeting]), "")
        XCTAssertEqual(VoiceEcho.strippingLeadingEcho("연습", of: [greeting]), "연습")
        XCTAssertEqual(VoiceEcho.strippingLeadingEcho("Look at me", of: [greeting]), "Look at me")
    }
    /// 11/06 device log: answers said over the app's list were dropped as echo.
    func testAnswerOverTheListIsAChoice() {
        let names=["찐테스트1", "11월 2일 16:40 무대", "11월 2일 13:32 무대"]
        let contexts=[["누리랩", "응가"], ["응가"], ["응가"]]
        XCTAssertTrue(VoiceEcho.isChoice("찐 테스트 일", names: names, contexts: contexts))
        XCTAssertTrue(VoiceEcho.isChoice("누리 랩", names: names, contexts: contexts))
        XCTAssertTrue(VoiceEcho.isChoice("첫 번째", names: names, contexts: contexts))
        // The app hearing its own list runs past one item; noise and the shared place are no answer.
        XCTAssertFalse(VoiceEcho.isChoice("찐테스트1 누리랩 응가", names: names, contexts: contexts))
        XCTAssertFalse(VoiceEcho.isChoice("응가", names: names, contexts: contexts))
        XCTAssertFalse(VoiceEcho.isChoice("공연 이름이나 번호를 말씀해주세요", names: names, contexts: contexts))
    }
}
