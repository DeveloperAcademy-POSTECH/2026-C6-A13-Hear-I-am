import XCTest
@testable import HearIAmCore

/// Words the phone answered with 「요청을 확실히 이해하지 못했어요」 (voice logs 10/29–11/13, typed input left
/// out), split by what was meant (#203). Names are the performances, stages and venues on the phone on 11/12.
final class VoiceChatterTests: XCTestCase {
    private let names = ["마루랩", "머지테스트", "무한성 제1장", "오늘도 출항하지 않습니다", "음성테스트", "응가", "장애물 음성 테스트", "확인점 2개",
                         "무대 스캔", "장면1", "찐테스트1"]
    private let contexts: [[String]] = [["효자아트홀"], [], ["CGV", "효자아트홀"], ["스트림도미넌트홀"], [], ["누리랩"], [], [],
                                        [], ["스트림도미넌트홀"], ["누리랩"]]

    /// Someone asked the app for something, said well or badly: never passed over.
    private let requests = ["무엇을 머지 테스트 무대 선택해 줘", "홈 화면으로", "세 번째 모습", "스캔 스캔.", "확인 테스트 연습 할래.",
                            "확인점 두개", "음성 보이스 종료", "확인 좀 2개 연습 할래", "네 번째 공연", "연수용", "장면 일 연습용",
                            "오늘은 사랑하지 않습니다 실전용", "마루 앱 실전용", "마지막", "Can Practice", "900", "선택해",
                            "누리 랩 실행", "저장된 무대 보여줘", "저장된 모델 보여줘", "연습용", "실전 용", "다음", "계속", "멈춰",
                            "P2로 다시 안내해 줘", "착용 다 했어", "이제 넘어가자", "잠깐만 기다려 봐", "효자아트홀", "마로 앱", "누리 랩", "작용 하래요", "연수병", "마루의 실전용"]
    /// Other people, the room and scraps of the app's own voice.
    private let chatter = ["어떤 거", "너무", "밤새 목록", "왜 이렇게 들어", "도 같은", "슬픈 거 말해는 들어", "어디로 봐야 돼",
                           "만약에", "새끼", "바이요", "그러니까", "개지", "헬로", "어떤 소녀를", "진짜", "무엇을", "네 되시나요",
                           "So", "Yeah so even both", "You go see it's really great Okay", "Okay okay", "I think we do",
                           "actually You go to book", "Okay In the need Okay", "you like some boa", "Okay it's good I'm gonna get the first",
                           "Yeah Yeah", "Yes Would you like it", "10 years ago", "Yes but would you like Just continue", "Yeah I did not quite",
                           "cold", "okay Is in the hotel", "my God You", "that's wonderful Come on", "well we can make a bomb",
                           "Okay that's horrible", "What were you hair for", "네 고맙을 가요", "무엇을 살", "드릴까요", "네 무엇요",
                           "무엇을 쓸까요", "유쾌한", "걸어빈 소리라떼 시간 다", "고키 40원 먹자", "연습실에서 오늘", "옥련 찾기"]

    private func isChatter(_ text: String) -> Bool {
        VoiceChatter.isChatter(text, names: names, contexts: contexts, screen: .stageList(stageCount: 8))
    }

    func testLoggedRequestsAreNeverPassedOver() {
        for text in requests { XCTAssertFalse(isChatter(text), text) }
    }

    func testLoggedChatterIsPassedOver() {
        let quiet = chatter.filter(isChatter)
        print("chatter passed over: \(quiet.count)/\(chatter.count)")
        chatter.filter { !isChatter($0) }.forEach { print("chatter still answered: 「\($0)」") }
        XCTAssertGreaterThanOrEqual(quiet.count, chatter.count * 2 / 3)
    }

    func testCommandWordsKeepTheAnswer() {
        // A word of a command keeps 「이해하지 못했어요」, so a request said badly is asked again.
        for text in ["다시 해 줘 그거", "멈출 수 있어", "연습 하고 싶어", "취소할래", "뒤로 가고 싶은데"] { XCTAssertFalse(isChatter(text), text) }
        XCTAssertTrue(VoiceChatter.isChatter("만약에"))
        XCTAssertFalse(VoiceChatter.isChatter("2번"))
        // A yes or no answers only a question.
        for text in ["응", "네", "Okay okay", "Yeah Yeah"] {
            XCTAssertTrue(VoiceChatter.isChatter(text), text)
            XCTAssertFalse(VoiceChatter.isChatter(text, expectsAnswer: true), text)
        }
        XCTAssertFalse(VoiceChatter.isChatter("아니"))
    }
}
