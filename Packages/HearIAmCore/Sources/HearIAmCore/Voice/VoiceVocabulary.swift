import Foundation

/// Sentences this app expects to hear, with rough weights, for teaching the recognizer (#92).
/// Everyday dictation writes the common word for a sound: 「2번」 becomes 「이번」 and 「피원」 becomes
/// 「비 일」. A custom language model built from these sentences makes the app's own words likelier.
public enum VoiceVocabulary {
    public struct Phrase: Equatable, Sendable {
        public let text: String
        public let count: Int
    }

    public static let version = "1"

    public static func phrases(stageNames: [String] = [], places: [String] = []) -> [Phrase] {
        var result: [Phrase] = []
        func add(_ text: String, _ count: Int) { result.append(Phrase(text: text, count: count)) }

        for call in ["Hear I am", "Here I am", "히얼아이엠"] {
            add(call, 3000)
            for command in ["계속", "멈춰", "다음", "시작"] { add("\(call) \(command)", 800) }
        }
        let commands = ["계속", "계속해 줘", "멈춰", "잠깐 멈춰 줘", "다음", "다음으로 넘어가 줘", "시작", "안내 시작",
                        "다시 말해 줘", "연습용", "연습용으로 할게", "실전용", "실전용으로 할게", "취소", "응", "아니",
                        "저장된 무대 다 불러와 줘", "무대 목록 보여 줘", "이전으로", "이전 단계로 돌아가 줘",
                        "무대 다시 선택", "다른 무대로 할래", "사전 저장된 공연 보여 줘",
                        "새 스캔", "새 무대 스캔할래"]
        for command in commands { add(command, 1000) }

        let spoken = ["원", "투", "쓰리", "포", "파이브", "식스", "세븐", "에잇", "나인"]
        for number in 1...9 {
            add("\(number)번", 1500)
            add("\(number)번 지점으로 돌아가 줘", 1500)
            add("\(number)번 지점으로 다시 안내해 줘", 1000)
            add("\(number)번 무대", 800)
            add("P\(number)", 1000)
            add("P\(number)로 돌아가 줘", 1500)
            add("피\(spoken[number - 1])", 1000)
            add("피\(spoken[number - 1])\(towards(spoken[number - 1])) 돌아가 줘", 1500)
        }
        for name in Set(stageNames.filter { !$0.isEmpty }) {
            add(name, 800)
            add("\(name) 열어 줘", 500)
            add("\(name)로 연습할게", 300)
        }
        for place in Set(places.filter { !$0.isEmpty }) {
            add("\(place) 관련 무대 찾아 줘", 300)
        }
        return result
    }

    /// 「으로」 after a final consonant other than ㄹ, else 「로」: 피원으로, 피투로.
    static func towards(_ word: String) -> String {
        guard let last = word.unicodeScalars.last, (0xAC00...0xD7A3).contains(last.value) else { return "로" }
        let final = (Int(last.value) - 0xAC00) % 28
        return final == 0 || final == 8 ? "로" : "으로"
    }
}
