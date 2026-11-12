import XCTest
@testable import HearIAmCore

/// English requests reach the same commands, searches and Home requests as their Korean ones (#183).
final class VoiceEnglishTests: XCTestCase {
    func testKoreanTextIsLeftAlone() {
        XCTAssertEqual(VoiceEnglish.canonical("계속해 줘"), "계속해 줘")
        XCTAssertEqual(VoiceEnglish.canonical("Vampire 열어줘"), "Vampire 열어줘")
        XCTAssertEqual(VoiceEnglish.canonical("P2로 돌아가"), "P2로 돌아가")
    }

    func testCommands() {
        XCTAssertEqual(VoiceCommandParser.parse("Continue."), .continueGuidance)
        XCTAssertEqual(VoiceCommandParser.parse("keep going"), .continueGuidance)
        XCTAssertEqual(VoiceCommandParser.parse("Wait a minute"), .pause)
        XCTAssertEqual(VoiceCommandParser.parse("Say that again, please."), .repeatInstruction)
        XCTAssertEqual(VoiceCommandParser.parse("I'm wearing it"), .next)
        XCTAssertEqual(VoiceCommandParser.parse("Next step"), .next)
        XCTAssertEqual(VoiceCommandParser.parse("Let's go"), .start)
        XCTAssertEqual(VoiceCommandParser.parse("Practice mode"), .practice)
        XCTAssertEqual(VoiceCommandParser.parse("Live"), .performance)
        XCTAssertEqual(VoiceCommandParser.parse("Never mind"), .cancel)
        XCTAssertEqual(VoiceCommandParser.parse("Go back"), .back)
        XCTAssertEqual(VoiceCommandParser.parse("Choose another stage"), .chooseStageAgain)
        XCTAssertEqual(VoiceCommandParser.parse("Yes, start"), .start)
        XCTAssertTrue(VoiceCommandParser.isClose("Close"))
        XCTAssertTrue(VoiceCommandParser.isClose("Goodbye."))
    }

    func testPoints() {
        XCTAssertEqual(VoiceCommandParser.parse("Go back to P2"), .returnToPoint(2))
        XCTAssertEqual(VoiceCommandParser.parse("point three"), .returnToPoint(3))
        XCTAssertEqual(VoiceCommandParser.parse("Take me back to pee one"), .returnToPoint(1))
        XCTAssertEqual(VoiceCommandParser.parse("go to the second point"), .returnToPoint(2))
        XCTAssertEqual(VoiceCommandParser.parse("P 4"), .returnToPoint(4))
    }

    func testListNumbers() {
        XCTAssertEqual(VoiceStageSearch.ordinal("Number two"), 2)
        XCTAssertEqual(VoiceStageSearch.ordinal("the third one"), 3)
        XCTAssertEqual(VoiceStageSearch.ordinal("Stage 1"), 1)
        // A bare 「to」 or 「for」 is a word, not a number.
        XCTAssertNil(VoiceStageSearch.ordinal("to"))
        XCTAssertNil(VoiceStageSearch.ordinal("for"))
    }

    func testStageByName() {
        let names = ["Vampire", "Main Hall", "Studio B"]
        XCTAssertEqual(VoiceStageSearch.resolve("Open Vampire", names: names), .selected(0))
        XCTAssertEqual(VoiceStageSearch.resolve("use the main hall stage", names: names), .selected(1))
        XCTAssertEqual(VoiceStageSearch.resolve("Vampire", names: names), .selected(0))
        XCTAssertEqual(VoiceStageSearch.resolve("Show all stages", names: names), .results(query: "전체", indices: [0, 1, 2]))
        XCTAssertEqual(VoiceStageSearch.resolve("find stages related to studio", names: names), .results(query: "studio", indices: [2]))
        XCTAssertTrue(VoiceStageSearch.isKeywordSearch("Search for hall"))
    }

    func testModeWithStage() {
        let split = VoiceCommandParser.splitMode("Vampire in practice mode")
        XCTAssertEqual(split?.mode, .practice)
        XCTAssertEqual(split?.rest, "vampire")
        XCTAssertEqual(VoiceCommandParser.splitMode("Open Main Hall live")?.mode, .performance)
        // A stage whose own name holds the word is still a name.
        XCTAssertEqual(VoiceStageSearch.resolve("Practice Room", names: ["Practice Room", "Vampire"]), .selected(0))
    }

    func testHomeRequests() {
        XCTAssertEqual(VoiceAppRequest.resolve("Scan a new stage"), .scan)
        XCTAssertEqual(VoiceAppRequest.resolve("New scan"), .scan)
        XCTAssertEqual(VoiceAppRequest.resolve("Show performance plans"), .plans)
        XCTAssertTrue(VoiceAppRequest.isRehearsal("Practice with a saved performance"))
        XCTAssertTrue(VoiceAppRequest.isRehearsal("Rehearse"))
        XCTAssertNil(VoiceAppRequest.resolve("Open Vampire"))
    }

    func testAnswers() {
        XCTAssertEqual(VoiceIntentCopy.answer("Yeah"), true)
        XCTAssertEqual(VoiceIntentCopy.answer("Sure."), true)
        XCTAssertEqual(VoiceIntentCopy.answer("Nope"), false)
        XCTAssertEqual(VoiceIntentCopy.answer("Never mind"), false)
        XCTAssertNil(VoiceIntentCopy.answer("Vampire"))
    }

    func testNoise() {
        XCTAssertNil(VoiceNoise.request("Um."))
        XCTAssertEqual(VoiceNoise.request("uh continue"), "continue")
    }

    func testFill() {
        XCTAssertEqual(HearText.fill("%@ of %@", [1, "two"]), "1 of two")
        XCTAssertEqual(HearText.fill("%2$@ before %1$@", ["a", "b"]), "b before a")
        XCTAssertEqual(HearText.fill("50% of %@", ["it"]), "50% of it")
        XCTAssertEqual(L("%@미터", 3), "3미터")
    }
}
