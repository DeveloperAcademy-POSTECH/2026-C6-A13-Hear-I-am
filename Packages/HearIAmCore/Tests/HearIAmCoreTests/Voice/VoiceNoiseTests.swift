import XCTest
@testable import HearIAmCore

final class VoiceNoiseTests: XCTestCase {
    func testNoiseIsDropped() {
        // Heard on the phone with nobody speaking to it (11/02, 11/03).
        for text in [".", "아.", "아", "이 .", "그", "S.", "아 .", "이요.", "음 음", " "] {
            XCTAssertNil(VoiceNoise.request(text), text)
        }
    }
    func testFillersAroundARequestAreDropped() {
        XCTAssertEqual(VoiceNoise.request("이 . 계속"), "계속")
        XCTAssertEqual(VoiceNoise.request("이  계속"), "계속")
        XCTAssertEqual(VoiceNoise.request("음 연습용."), "연습용")
        XCTAssertEqual(VoiceNoise.request("2번 아"), "2번")
    }
    func testShortRequestsStay() {
        for text in ["네", "응", "예.", "2", "다음", "취소", "연습용", "확인점 2개 연습할래"] {
            XCTAssertNotNil(VoiceNoise.request(text), text)
        }
        // A filler inside the request is part of it.
        XCTAssertEqual(VoiceNoise.request("음성테스트 이 무대"), "음성테스트 이 무대")
    }
}
