import XCTest
@testable import HearIAmCore

final class VoiceAppRequestTests: XCTestCase {
    func testPlanRequests() {
        for text in ["사전 저장된 공연장 보여줘", "사전에 저장한 공연 열어 줘", "미리 그린 동선 보여 줘", "공연 도면 뭐 있어"] {
            XCTAssertEqual(VoiceAppRequest.resolve(text), .plans, text)
        }
        for text in ["의자 테스트 열어 줘", "저장된 무대 다 불러와 줘", "효자아트홀 관련 무대 찾아 줘", "스캔한 무대 보여 줘"] {
            XCTAssertNil(VoiceAppRequest.resolve(text), text)
        }
    }
    func testScanRequests() {
        for text in ["새 스캔", "새 스캔 시작해 줘", "무대 스캔할래", "스캔하자", "새로 스캔해 줘", "새 무대 만들어 줘", "스캔 열어 줘"] {
            XCTAssertEqual(VoiceAppRequest.resolve(text), .scan, text)
        }
        // Plans come first: their answer is about scanning, but the request is to see them.
        XCTAssertEqual(VoiceAppRequest.resolve("사전 저장된 공연 스캔할 때 볼래"), .plans)
    }
    func testPlansAnswerNamesThemAndSaysTheyNeedAScan() {
        XCTAssertEqual(VoiceAppRequest.plansAnswer(names: ["포스텍"]).first, "공연 사전 저장에 1개가 있어요. 포스텍.")
        XCTAssertTrue(VoiceAppRequest.plansAnswer(names: ["포스텍"]).last!.contains("스캔"))
        XCTAssertEqual(VoiceAppRequest.plansAnswer(names: (1...7).map { "공연\($0)" }).first,
                       "공연 사전 저장에 7개가 있어요. 공연1, 공연2, 공연3, 공연4, 공연5 외 2개.")
        XCTAssertEqual(VoiceAppRequest.plansAnswer(names: []), ["공연 사전 저장에 저장한 공연이 없어요."])
    }
}
