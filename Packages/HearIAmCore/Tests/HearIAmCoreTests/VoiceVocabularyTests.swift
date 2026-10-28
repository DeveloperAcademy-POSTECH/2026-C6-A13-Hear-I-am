import XCTest
@testable import HearIAmCore

/// #92: the sentences taught to the recognizer cover the app's own words and every phrase still parses.
final class VoiceVocabularyTests: XCTestCase {
    func testTeachesNumbersAsDigitsAndPointNames() {
        let texts = Set(VoiceVocabulary.phrases().map(\.text))
        for text in ["2번 지점으로 돌아가 줘", "피원으로 돌아가 줘", "피투로 돌아가 줘", "P3로 돌아가 줘", "히얼아이엠 멈춰", "저장된 무대 다 불러와 줘"] {
            XCTAssertTrue(texts.contains(text), text)
        }
        XCTAssertFalse(texts.contains { $0.contains("이번") })
    }
    func testPointPhrasesParseToTheirPoint() {
        for number in 1...9 {
            XCTAssertEqual(VoiceCommandParser.parse("\(number)번 지점으로 돌아가 줘"), .returnToPoint(number))
            XCTAssertEqual(VoiceCommandParser.parse("P\(number)로 돌아가 줘"), .returnToPoint(number))
        }
    }
    func testStageNamesAreIncludedOnce() {
        let phrases = VoiceVocabulary.phrases(stageNames: ["의자 테스트", "의자 테스트"], places: ["효자아트홀"])
        XCTAssertEqual(phrases.filter { $0.text == "의자 테스트" }.count, 1)
        XCTAssertTrue(phrases.contains { $0.text == "효자아트홀 관련 무대 찾아 줘" })
        XCTAssertTrue(phrases.allSatisfy { $0.count > 0 })
    }
}
