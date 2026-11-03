import XCTest
@testable import HearIAmCore

final class VoiceAutocorrectTests: XCTestCase {
    let lexicon = VoiceAutocorrect.lexicon(VoiceVocabulary.phrases(stageNames: ["확인점 2개", "머지테스트", "음성테스트1"]).map(\.text))

    func testMisheardAppWordsAreFixed() {
        // 11/03 device test.
        XCTAssertEqual(VoiceAutocorrect.correct("저장된 모대 보여줘", lexicon: lexicon), "저장된 무대 보여줘")
        XCTAssertEqual(VoiceAutocorrect.correct("모대를 보여줘", lexicon: lexicon), "무대를 보여줘")
        XCTAssertEqual(VoiceAutocorrect.correct("저장된 공언 보여줘.", lexicon: lexicon), "저장된 공연 보여줘.")
        XCTAssertEqual(VoiceAutocorrect.correct("머지테수트 열어 줘", lexicon: lexicon), "머지테스트 열어 줘")
        XCTAssertEqual(VoiceAutocorrect.correct("연숩용으로 할게", lexicon: lexicon), "연습용으로 할게")
    }

    func testRightAndUnrelatedWordsStay() {
        for text in ["저장된 무대 보여줘", "3번", "Here I am", "오늘 날씨 어때", "네", "스캔", "확인점 2개"] {
            XCTAssertEqual(VoiceAutocorrect.correct(text, lexicon: lexicon), text, text)
        }
    }

    func testTwoEquallyCloseWordsAreNotGuessed() {
        let lexicon: Set<String> = ["무대", "모래"]
        XCTAssertEqual(VoiceAutocorrect.correct("모대", lexicon: lexicon), "모대")
    }
}
