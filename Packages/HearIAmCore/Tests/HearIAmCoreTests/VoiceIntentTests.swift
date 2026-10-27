import XCTest
@testable import HearIAmCore

/// #87: a model guess only ever maps to what the current screen offers, and a guess is asked back first.
final class VoiceIntentTests: XCTestCase {
    private let guidance = VoiceScreen.guidance(pointCount: 5)

    func testSureGuessActsAndUnsureGuessAsks() {
        XCTAssertEqual(VoiceIntentDecision.from(action:"continueGuidance",number:0,sure:true,screen:guidance),.command(.continueGuidance))
        XCTAssertEqual(VoiceIntentDecision.from(action:"pause",number:0,sure:false,screen:guidance),.confirm(.pause))
    }
    func testPointMustBeOnTheRoute() {
        XCTAssertEqual(VoiceIntentDecision.from(action:"returnToPoint",number:3,sure:true,screen:guidance),.confirm(.returnToPoint(3)))
        XCTAssertEqual(VoiceIntentDecision.from(action:"returnToPoint",number:0,sure:true,screen:guidance),.none)
        XCTAssertEqual(VoiceIntentDecision.from(action:"returnToPoint",number:6,sure:true,screen:guidance),.none)
        XCTAssertEqual(VoiceIntentDecision.from(action:"returnToPoint",number:2,sure:true,screen:.guidance(pointCount:0)),.none)
    }
    func testAnythingElseIsNotACommand() {
        XCTAssertEqual(VoiceIntentDecision.from(action:"none",number:0,sure:true,screen:guidance),.none)
        XCTAssertEqual(VoiceIntentDecision.from(action:"dance",number:0,sure:true,screen:guidance),.none)
    }
    func testEachScreenOnlyOffersItsOwnActions() {
        XCTAssertEqual(VoiceIntentDecision.from(action:"practice",number:0,sure:true,screen:guidance),.none)
        XCTAssertEqual(VoiceIntentDecision.from(action:"showAllStages",number:0,sure:true,screen:.modeChoice),.none)
        XCTAssertEqual(VoiceIntentDecision.from(action:"practice",number:0,sure:true,screen:.modeChoice),.command(.practice))
        XCTAssertEqual(VoiceIntentDecision.from(action:"next",number:0,sure:true,screen:.preparation),.command(.next))
        XCTAssertEqual(VoiceIntentDecision.from(action:"returnToPoint",number:2,sure:true,screen:.preparation),.none)
        let instructions=VoiceIntentDecision.instructions(for:.modeChoice)
        XCTAssertTrue(instructions.contains("practice:"))
        XCTAssertFalse(instructions.contains("returnToPoint:"))
    }
    func testStageListCanReadAllOrChooseByNumber() {
        let list=VoiceScreen.stageList(stageCount:3)
        XCTAssertEqual(VoiceIntentDecision.from(action:"showAllStages",number:0,sure:true,screen:list),.command(.showAllStages))
        XCTAssertEqual(VoiceIntentDecision.from(action:"chooseStage",number:2,sure:true,screen:list),.confirm(.chooseStage(2)))
        XCTAssertEqual(VoiceIntentDecision.from(action:"chooseStage",number:4,sure:true,screen:list),.none)
        XCTAssertEqual(VoiceIntentDecision.from(action:"chooseStage",number:1,sure:true,screen:.stageList(stageCount:0)),.none)
        XCTAssertEqual(VoiceIntentDecision.from(action:"showAllStages",number:0,sure:true,screen:.stageList(stageCount:0)),.command(.showAllStages))
        XCTAssertTrue(VoiceIntentDecision.instructions(for:list).contains("showAllStages:"))
    }
    func testYesAndNoAnswers() {
        for text in ["응","네.","그래 ","좋아요","OK"] { XCTAssertEqual(VoiceIntentCopy.answer(text),true,text) }
        for text in ["아니","아니요!","됐어"] { XCTAssertEqual(VoiceIntentCopy.answer(text),false,text) }
        XCTAssertNil(VoiceIntentCopy.answer("계속 해 줘"))
        XCTAssertEqual(VoiceIntentCopy.question(.returnToPoint(2)),"2번 지점으로 다시 안내할까요?")
        XCTAssertEqual(VoiceIntentCopy.question(.showAllStages),"저장된 무대를 모두 읽어드릴까요?")
    }
}
