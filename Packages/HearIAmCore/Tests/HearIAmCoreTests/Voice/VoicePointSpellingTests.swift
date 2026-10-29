import XCTest
@testable import HearIAmCore

/// #90: point names spelled by sound become 「P1」 before the model reads them.
final class VoicePointSpellingTests: XCTestCase {
    func testSoundSpellingsBecomePointNames() {
        let cases = [("삐원으로 가", "P1으로 가"), ("키원으로 돌아가", "P1으로 돌아가"), ("피윈으로 돌아가 줘", "P1으로 돌아가 줘"),
                     ("비원 쪽으로 가볼까", "P1 쪽으로 가볼까"), ("피엘로 돌아가", "P1로 돌아가"), ("비 투로 가자", "P2로 가자"),
                     ("피쓰리로", "P3로"), ("삐 파이브에서 멈춰", "P5에서 멈춰")]
        for (text, expected) in cases { XCTAssertEqual(VoicePointSpelling.normalized(text), expected, text) }
    }
    func testOrdinaryWordsStayAsTheyAre() {
        for text in ["비가 와", "피아노 쳐 줘", "키가 커", "삐뚤어졌어", "비빔밥", "계속", "피곤해", "비상구로 가"] {
            XCTAssertEqual(VoicePointSpelling.normalized(text), text, text)
        }
    }
}
