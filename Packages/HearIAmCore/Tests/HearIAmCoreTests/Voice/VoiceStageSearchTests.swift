import XCTest
@testable import HearIAmCore

final class VoiceStageSearchTests: XCTestCase {
    let names=["효자아트홀 I believe", "효자아트홀 입장 동선", "연습실 A Look at me"]
    func testExactNameAdvancesWithoutConfirmation() {
        XCTAssertEqual(VoiceStageSearch.resolve("효자아트홀 I believe", names: names), .selected(0))
        XCTAssertEqual(VoiceStageSearch.resolve("효자아트홀 i BELIEVE 선택해줘", names: names), .selected(0))
        XCTAssertEqual(VoiceStageSearch.resolve("효자아트홀 I believe를 선택해주세요", names: names), .selected(0))
    }
    func testRelatedSearchReturnsAllMatchingStages() {
        XCTAssertEqual(VoiceStageSearch.resolve("효자아트홀과 관련된 무대 열어줘", names: names), .results(query: "효자아트홀", indices: [0,1]))
        XCTAssertEqual(VoiceStageSearch.resolve("효자 아트홀 무대 찾아줘", names: names), .results(query: "효자아트홀", indices: [0,1]))
    }
    func testSingleKeywordResultStillRequiresChoosingTheStage() {
        XCTAssertEqual(VoiceStageSearch.resolve("Look at me 관련 무대 보여줘", names: names), .results(query: "lookatme", indices: [2]))
    }
    func testDuplicateNamesRemainAmbiguous() {
        XCTAssertEqual(VoiceStageSearch.resolve("같은 무대", names: ["같은 무대","같은 무대"]), .results(query: "같은 무대", indices: [0,1]))
    }
    func testEmptyAndNoMatches() {
        XCTAssertEqual(VoiceStageSearch.resolve("  ", names: names), .none)
        XCTAssertEqual(VoiceStageSearch.resolve("부산 관련 무대 열어줘", names: names), .results(query: "부산", indices: []))
    }
    func testOrdinalAndAllResults() {
        XCTAssertEqual(VoiceStageSearch.ordinal("두 번째 선택해줘"), 2)
        XCTAssertEqual(VoiceStageSearch.ordinal("1번"), 1)
        XCTAssertNil(VoiceStageSearch.ordinal("1번 말고 2번"))
        XCTAssertEqual(VoiceStageSearch.resolve("전체 목록 보여줘", names: names), .results(query: "전체", indices: [0,1,2]))
    }
    func testPlaceAndFolderSearchKeepsDuplicatePerformancesDistinct() {
        let names=["Look at me","Look at me","입장 동선"]
        let contexts=[["효자아트홀"],["대구공연예술연습공간","대연습실"],["효자아트홀"]]
        XCTAssertEqual(VoiceStageSearch.resolve("Look at me",names:names,contexts:contexts),.results(query:"Look at me",indices:[0,1]))
        XCTAssertEqual(VoiceStageSearch.resolve("효자아트홀 Look at me",names:names,contexts:contexts),.selected(0))
        XCTAssertEqual(VoiceStageSearch.resolve("대연습실 Look at me 선택해줘",names:names,contexts:contexts),.selected(1))
        XCTAssertEqual(VoiceStageSearch.resolve("효자아트홀과 관련된 무대 열어줘",names:names,contexts:contexts),.results(query:"효자아트홀",indices:[0,2]))
        XCTAssertEqual(VoiceStageSearch.resolve("대연습실 무대 찾아줘",names:names,contexts:contexts),.results(query:"대연습실",indices:[1]))
        // The new Home's example sentence (IA 10/29).
        XCTAssertEqual(VoiceStageSearch.resolve("효자아트홀에 저장된 공연 리스트 찾아줘",names:names,contexts:contexts),.results(query:"효자아트홀",indices:[0,2]))
        XCTAssertEqual(VoiceStageSearch.resolve("저장된 공연 리스트 보여줘",names:names,contexts:contexts),.results(query:"전체",indices:[0,1,2]))
    }

    func testKeywordSearchIsNotHandedToTheModel() {
        XCTAssertTrue(VoiceStageSearch.isKeywordSearch("강당 관련 무대 찾아줘"))
        XCTAssertTrue(VoiceStageSearch.isKeywordSearch("강당 검색해 줘"))
        XCTAssertFalse(VoiceStageSearch.isKeywordSearch("저장된 무대 다 불러와 줘"))
        XCTAssertFalse(VoiceStageSearch.isKeywordSearch("무대 목록 다 보여줘"))
        XCTAssertFalse(VoiceStageSearch.isKeywordSearch("오늘 날씨 어때"))
    }

    /// The stage names saved on the 16 Pro Max on 11/01.
    let phoneNames=["무대 스캔", "333", "테스트2", "무대 스캔", "4444", "무대 스캔", "장애물 음성 테스트", "무대 스캔", "머지테스트", "확인점 2개"]
    func testNameInsideALongerRequestSelectsThatStage() {
        XCTAssertEqual(VoiceStageSearch.resolve("머지테스트 열람", names: phoneNames), .selected(8))
        XCTAssertEqual(VoiceStageSearch.resolve("이번 머지테스트 열람", names: phoneNames), .selected(8))
        XCTAssertEqual(VoiceStageSearch.resolve("머지테스트 하고 싶어", names: ["테스트", "머지테스트"]), .selected(1))
        XCTAssertEqual(VoiceStageSearch.resolve("무대 스캔 보여줘", names: phoneNames), .results(query: "무대 스캔 보여줘", indices: [0, 3, 5, 7]))
        XCTAssertEqual(VoiceStageSearch.resolve("연남", names: phoneNames), .results(query: "연남", indices: []))
    }
    func testModelStageGuessMustBeNamedOrNumbered() {
        XCTAssertFalse(VoiceStageSearch.mentions("연남", number: 9, name: "머지테스트"))
        XCTAssertTrue(VoiceStageSearch.mentions("머지테스트 연남", number: 9, name: "머지테스트"))
        XCTAssertTrue(VoiceStageSearch.mentions("머지 쪽 거", number: 9, name: "머지테스트"))
        XCTAssertTrue(VoiceStageSearch.mentions("구번 거", number: 9, name: "머지테스트"))
        XCTAssertTrue(VoiceStageSearch.mentions("두 번째 거", number: 2, name: "333"))
        XCTAssertFalse(VoiceStageSearch.mentions("열람", number: 2, name: "333"))
    }
}
