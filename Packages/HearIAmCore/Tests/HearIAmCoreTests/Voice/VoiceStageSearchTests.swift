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
    func testNamesHeardSlightlyWrong() {
        let names=["333", "4444", "머지테스트", "무대 스캔", "확인점 2개", "음성테스트1"]
        // 11/03 device log: the same stage said four ways.
        for text in ["확인점 두개", "확인 점 2개", "확인 좀 2개 연습 할래", "확인점 조개"] {
            XCTAssertEqual(VoiceStageSearch.resolve(text, names: names), .selected(4), text)
        }
        // Too far from any name, or close to two at once, is not a guess.
        XCTAssertEqual(VoiceStageSearch.resolve("오늘 날씨 어때", names: names), .results(query: "오늘날씨어때", indices: []))
        XCTAssertNil(VoiceStageSearch.nearlyNamed("음성테스트2", names: ["음성테스트1", "음성테스트3"].map(VoiceStageSearch.normalized)))
    }
    func testNumberWithName() {
        let same=["무대 스캔", "무대 스캔", "무대 스캔", "무대 스캔"]
        XCTAssertEqual(VoiceStageSearch.numbered("3번 무대 스캔", names: same), 3)
        XCTAssertEqual(VoiceStageSearch.numbered("3번 무대스캔으로", names: same), 3)
        XCTAssertEqual(VoiceStageSearch.numbered("세번째 무대 스캔", names: same), 3)
        XCTAssertEqual(VoiceStageSearch.numbered("삼번 무대", names: same), 3)
        XCTAssertNil(VoiceStageSearch.numbered("7번 무대 스캔", names: same))
        XCTAssertNil(VoiceStageSearch.numbered("2번 머지테스트", names: ["머지테스트", "무대 스캔"]))
        XCTAssertNil(VoiceStageSearch.numbered("무대 스캔", names: same))
    }
    /// 11/06 device log: 응가 held 찐테스트1 (at 누리랩) and two dated stages.
    func testPlaceWithOneStageSelectsIt() {
        let names=["찐테스트1", "11월 2일 16:40 무대", "11월 2일 13:32 무대"]
        let contexts=[["누리랩", "응가"], ["응가"], ["응가"]]
        XCTAssertEqual(VoiceStageSearch.resolve("누리 랩", names: names, contexts: contexts), .selected(0))
        XCTAssertEqual(VoiceStageSearch.resolve("누리 랩 실행", names: names, contexts: contexts), .selected(0))
        XCTAssertEqual(VoiceStageSearch.resolve("누리랩으로 실행해줘", names: names, contexts: contexts), .selected(0))
        // A place several stages share is still a list, and so is a search asked for as one.
        XCTAssertEqual(VoiceStageSearch.resolve("응가", names: names, contexts: contexts), .results(query: "응가", indices: [0, 1, 2]))
        XCTAssertEqual(VoiceStageSearch.resolve("누리랩 무대 찾아줘", names: names, contexts: contexts), .results(query: "누리랩", indices: [0]))
        // 「실행」 alone names nothing.
        XCTAssertEqual(VoiceStageSearch.resolve("실행", names: names, contexts: contexts), .none)
    }
    /// #192: a number in a name is said as a word, and dictation writes it that way (「장면 일」, 11/11).
    func testNameWithNumberIsFoundBySpokenNumber() {
        XCTAssertEqual(VoiceStageSearch.spoken("장면1"), "장면일")
        XCTAssertEqual(VoiceStageSearch.spoken("제12장"), "제십이장")
        XCTAssertEqual(VoiceStageSearch.spoken("무대20"), "무대이십")
        XCTAssertEqual(VoiceStageSearch.spoken("2026"), "이영이육")
        XCTAssertEqual(VoiceStageSearch.spoken("효자아트홀"), "효자아트홀")
        let scenes=["장면1", "장면2", "무한성 제1장"]
        XCTAssertEqual(VoiceStageSearch.resolve("장면 일", names: scenes), .selected(0))
        XCTAssertEqual(VoiceStageSearch.resolve("장면 이 선택해줘", names: scenes), .selected(1))
        XCTAssertEqual(VoiceStageSearch.resolve("무한성 제일장", names: scenes), .selected(2))
        XCTAssertEqual(VoiceStageSearch.resolve("장면1", names: scenes), .selected(0))
    }
    /// #192: 「마루 앱」 for 「마루랩」 (11/12). Three letters are too few for a letter to be wrong anywhere in
    /// a longer request, so only the whole request one sound away counts, and only for one name.
    func testThreeLetterNameOneSoundAway() {
        let list=["마루랩", "머지테스트", "응가"]
        XCTAssertEqual(VoiceStageSearch.resolve("마루 앱", names: list), .selected(0))
        XCTAssertEqual(VoiceStageSearch.resolve("마루냅 선택해줘", names: list), .selected(0))
        XCTAssertEqual(VoiceStageSearch.resolve("바르앱", names: list), .results(query: "바르앱", indices: []))
        XCTAssertEqual(VoiceStageSearch.resolve("오늘 마루 앱 어때", names: list), .results(query: "오늘마루앱어때", indices: []))
        XCTAssertEqual(VoiceStageSearch.resolve("마루냅", names: ["마루랩", "마루맵"]), .results(query: "마루냅", indices: []))
        XCTAssertEqual(VoiceStageSearch.resolve("은가", names: list), .results(query: "은가", indices: []))
    }
    /// #192: 「오늘은 사랑하지 않습니다」 for 「오늘도 출항하지 않습니다」 (11/11): three letters of eleven.
    func testLongNameMayBeOffByThreeLetters() {
        let list=["오늘도 출항하지 않습니다", "마루랩", "장애물 음성 테스트"]
        XCTAssertEqual(VoiceStageSearch.resolve("오늘은 사랑하지 않습니다", names: list), .selected(0))
        XCTAssertEqual(VoiceStageSearch.resolve("오늘은 출항 하지 않습니다", names: list), .selected(0))
        XCTAssertEqual(VoiceStageSearch.resolve("내일은 사랑하지 않겠습니다", names: list), .results(query: "내일은사랑하지않겠습니다", indices: []))
        XCTAssertEqual(VoiceStageSearch.resolve("장애인 음성 데스크", names: list), .results(query: "장애인음성데스크", indices: []))
    }
    /// #192: 「세 번째 모습」 (11/02) and 「네 번째 공연」 (11/03) pick by position whatever the item is called.
    func testOrdinalWithAWordAfterIt() {
        let list=["마루랩", "머지테스트", "무한성 제1장", "오늘도 출항하지 않습니다"]
        XCTAssertEqual(VoiceStageSearch.numbered("세 번째 모습", names: list), 3)
        XCTAssertEqual(VoiceStageSearch.numbered("네 번째 공연", names: list), 4)
        XCTAssertEqual(VoiceStageSearch.numbered("두 번째 걸로", names: list), 2)
        XCTAssertEqual(VoiceStageSearch.numbered("2번째 거", names: list), 2)
        XCTAssertNil(VoiceStageSearch.numbered("다섯 번째 공연", names: list))
        XCTAssertNil(VoiceStageSearch.numbered("세 번째 줄에 서 있어", names: list))
        XCTAssertNil(VoiceStageSearch.numbered("3번 머지테스트", names: list))
        let nights=["세 번째 밤", "첫 번째 밤", "두 번째 밤"]
        XCTAssertNil(VoiceStageSearch.numbered("세 번째 밤", names: nights))
        XCTAssertEqual(VoiceStageSearch.resolve("세 번째 밤", names: nights), .selected(0))
        XCTAssertEqual(VoiceStageSearch.numbered("마지막 공연", names: list), 4)
        XCTAssertEqual(VoiceStageSearch.numbered("맨 마지막 거", names: list), 4)
        XCTAssertEqual(VoiceStageSearch.numbered("맨 위에 거", names: list), 1)
        XCTAssertEqual(VoiceStageSearch.numbered("맨 처음 걸로 할게", names: list), 1)
        XCTAssertNil(VoiceStageSearch.numbered("처음", names: list))
        XCTAssertNil(VoiceStageSearch.numbered("마지막 인사", names: list))
        XCTAssertNil(VoiceStageSearch.numbered("마지막 공연", names: ["마지막 공연", "첫 공연"]))
    }
    /// #192: asking to see what is saved, with the noun misheard or the verb cut short (11/03, 11/08).
    func testAskingForEverythingSaved() {
        let all=VoiceStageMatch.results(query: "전체", indices: [0,1,2])
        for text in ["저장된 무대 보여", "저장된 모델 보여줘", "저장된 모대 보여줘", "무대 보여줘", "공연 목록 알려줘", "저장된 공연 읽어줘", "무대 뭐 있어"] {
            XCTAssertEqual(VoiceStageSearch.resolve(text, names: names), all, text)
        }
        XCTAssertEqual(VoiceStageSearch.resolve("저장된 연습실 보여줘", names: names), .selected(2))
        XCTAssertEqual(VoiceStageSearch.resolve("저녁내 모드 보여줘", names: names), .results(query: "저녁내모드", indices: []))
        XCTAssertEqual(VoiceStageSearch.resolve("효자아트홀 보여줘", names: names), .results(query: "효자아트홀", indices: [0,1]))
    }
    /// #192: the nearest-sounding name is offered with a question when nothing else found it.
    func testClosestSoundingName() {
        let list=["마루랩", "머지테스트", "무한성 제1장", "오늘도 출항하지 않습니다", "음성테스트", "응가", "장애물 음성 테스트", "확인점 2개"]
        XCTAssertEqual(VoiceStageSearch.closest("마로 앱", names: list), 0)
        XCTAssertEqual(VoiceStageSearch.closest("머지 테스터로 할게", names: list), 1)
        XCTAssertEqual(VoiceStageSearch.closest("무안성 제일장", names: list), 2)
        XCTAssertEqual(VoiceStageSearch.closest("화긴점 두 개", names: list), 7)
        XCTAssertEqual(VoiceStageSearch.closest("장애물 음성 데스트", names: list), 6)
        for text in ["어떤", "어떤 거", "그러니까", "열람", "너무", "만약에", "새끼", "개지", "자기", "바이요", "도 같은", "고키 40원 먹자", "왜 이렇게 들어",
                     "바른 인식을 해야 되는데", "슬픈 거 말해는 들어", "연습실에서 오늘", "어디로 봐야 돼", "Siri야", "야", "개 찾기 어떤", "헬로", "해피벌스데이",
                     "세벌 시티", "선택해", "밤새 목록", "옥련 찾기", "연남", "장면 일", "은가", "",
                     "전화 왔대 자기 노래 노래 몇 시년 했는데 좀 랩 1번 한 걸로 조서 받"] {
            XCTAssertNil(VoiceStageSearch.closest(text, names: list), text)
        }
        // Two names as near as each other, or the same name twice, are not guessed between.
        XCTAssertNil(VoiceStageSearch.closest("마루냅", names: ["마루랩", "마루맵"]))
        // All but the last letter of one name (11/14): asked back. Talk that only starts like a long name is not.
        XCTAssertEqual(VoiceStageSearch.closest("마루의", names: list), 0)
        XCTAssertNil(VoiceStageSearch.closest("오늘 점심", names: list))
        XCTAssertNil(VoiceStageSearch.closest("마루", names: list))
        XCTAssertNil(VoiceStageSearch.closest("무대 스켄", names: ["무대 스캔", "무대 스캔"]))
    }
}
