import XCTest
@testable import HearIAmCore

/// #90: every spelling dictation gives the app name opens the agent; ordinary speech does not.
final class VoiceWakeWordTests: XCTestCase {
    func testSpellingsOfTheAppNameMatch() {
        for text in ["히얼아이엠", "히얼 아이엠", "히어 아이 엠", "히어라이엠", "Hear I am", "hear i am!", "here I am", "어 히얼아이엠 무대 준비해 줘", "히어 I am 멈춰"] {
            XCTAssertTrue(VoiceWakeWord.matches(text), text)
        }
    }
    func testOrdinarySpeechDoesNotMatch() {
        for text in ["", "아이엠", "히어로", "여기 있어", "저장된 무대 다 불러와 줘", "I am here"] {
            XCTAssertFalse(VoiceWakeWord.matches(text), text)
        }
    }
    func testRequestAfterTheCall() {
        XCTAssertEqual(VoiceWakeWord.request(in:"히얼아이엠, 멈춰"),"멈춰")
        XCTAssertEqual(VoiceWakeWord.request(in:"히어 아이 엠 P2로 다시 안내해 줘"),"P2로 다시 안내해 줘")
        XCTAssertEqual(VoiceWakeWord.request(in:"Hear I am"),"")
        XCTAssertEqual(VoiceWakeWord.request(in:"히얼아이엠!"),"")
        XCTAssertNil(VoiceWakeWord.request(in:"멈춰"))
        XCTAssertEqual(VoiceWakeWord.request(in:"히어 I am 멈춰"),"멈춰")
    }
    func testOccurrencesInAGrowingTranscript() {
        XCTAssertEqual(VoiceWakeWord.occurrences(in:"Here I am"),1)
        XCTAssertEqual(VoiceWakeWord.occurrences(in:"Here I am stop here I am"),2)
        XCTAssertEqual(VoiceWakeWord.occurrences(in:"hello there"),0)
    }
}
