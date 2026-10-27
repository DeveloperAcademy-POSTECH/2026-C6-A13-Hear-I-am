import XCTest
@testable import HearIAmCore

final class VoiceCommandParserTests: XCTestCase {
    func testPointTwoRecognitionVariants() {
        for text in ["P2", "p 2", "P2 지점으로 다시 안내해줘", "P2로 다시 안내해 주세요.",
                     "피투로 돌아가 줘", "피 이 지점으로 안내해줘", "피2로 데려다줘", "2번 지점으로 다시 안내해주세요",
                     "두 번째 지점으로 다시 안내해줘", "두번째로 안내해줘", "P2번 지점으로 안내해줘",
                     "다시 P2로 안내해줘", "Take me back to P2", "return to point 2", "p two please"] {
            XCTAssertEqual(VoiceCommandParser.parse(text),.returnToPoint(2),text)
        }
    }
    func testOtherPointIDsRemainOriginalIndicesAndRequireRouteValidation() {
        for (text,index) in [("첫 번째 지점으로 안내해줘",1),("피 십이 지점으로 안내해줘",12),
                             ("피이십으로 안내해줘",20),("P0",0),("P99로 안내해줘",99),("세번째 지점으로",3)] {
            XCTAssertEqual(VoiceCommandParser.parse(text),.returnToPoint(index),text)
        }
    }
    func testFieldMishearingsOfPointOne() {
        // Transcripts from the 10/28 device test where P1 was said.
        for text in ["비 일로 돌아가", "피엘로 돌아가", "비닐로 들어가", "피원으로 가 줘", "비원으로 돌아가자"] {
            XCTAssertEqual(VoiceCommandParser.parse(text),.returnToPoint(1),text)
        }
        XCTAssertEqual(VoiceCommandParser.parse("비투로 돌아가"),.returnToPoint(2))
    }
    func testNumbersWrittenAsEverydayWords() {
        // 「2번」 sounds like 「이번」, 「4번」 like 「사번」.
        let cases:[(String,Int)]=[("이번 지점으로 돌아가",2),("이번으로 돌아가 줘",2),("사번 지점으로 다시 안내해 줘",4),("일번으로 가",1)]
        for (text,index) in cases { XCTAssertEqual(VoiceCommandParser.parse(text),.returnToPoint(index),text) }
        for text in ["이번엔 계속 가자", "이번에 멈춰", "이번 거 좋다"] { XCTAssertNil(VoiceCommandParser.parse(text),text) }
        XCTAssertEqual(VoiceStageSearch.ordinal("이번"),2)
        XCTAssertEqual(VoiceStageSearch.ordinal("이번 무대"),2)
        XCTAssertEqual(VoiceStageSearch.ordinal("삼번 선택해 줘"),3)
        XCTAssertNil(VoiceStageSearch.ordinal("이번에"))
    }
    func testLeadingYesBeforeACommand() {
        let cases:[(String,VoiceCommand)]=[("네 시작",.start),("응 계속",.continueGuidance),("자, 다음",.next),("어 멈춰",.pause),("네 P2로 돌아가",.returnToPoint(2))]
        for (text,command) in cases { XCTAssertEqual(VoiceCommandParser.parse(text),command,text) }
        XCTAssertEqual(VoiceCommandParser.parse("네 번째 지점으로"),.returnToPoint(4))
        for text in ["네", "네 그거", "응 계속하지 마", "비닐 봉지", "피엘이 뭐야"] { XCTAssertNil(VoiceCommandParser.parse(text),text) }
    }
    func testLimitedCommands() {
        let cases:[(String,VoiceCommand)]=[
            ("계속",.continueGuidance),("계속 진행해줘",.continueGuidance),("Resume",.continueGuidance),
            ("멈춰",.pause),("잠깐 멈춰줘",.pause),("Pause",.pause),
            ("다시 말해줘",.repeatInstruction),("다시 들려주세요",.repeatInstruction),
            ("다음",.next),("다음으로 넘어가줘",.next),("착용 완료",.next),
            ("안내 시작",.start),("시작해주세요",.start),
            ("연습용으로 할게",.practice),("연습",.practice),
            ("실전용으로 할게요",.performance),("공연 모드",.performance),
            ("취소",.cancel),("아니요",.cancel)]
        for (text,command) in cases { XCTAssertEqual(VoiceCommandParser.parse(text),command,text) }
    }
    func testAmbiguityNegationAndUnrelatedSpeechDoNotMove() {
        for text in ["P2 아니 P3", "P2 말고 P3로 안내해줘", "P2와 P3", "P2 P2", "P2로 가지 마",
                     "P2 안내하지 마", "P2가 어디야", "P2를 삭제해줘", "2번 무대", "계속하지 마",
                     "멈추지 마", "연습하지마", "P-2", "P2000", "hello", "", "   "] {
            XCTAssertNil(VoiceCommandParser.parse(text),text)
        }
    }
    func testLongOrMalformedTextIsRejected() {
        XCTAssertNil(VoiceCommandParser.parse(String(repeating:"P2 ",count:100)))
        XCTAssertNil(VoiceCommandParser.parse("https://example.com/p2"))
        XCTAssertNil(VoiceCommandParser.parse("P2로 안내하고 P3로 이동해줘"))
    }
}
