import Foundation

public enum Presets {
    public static let all: [PatternSet] = {
        func pair(_ a: Double, _ b: Double, softFirst: Bool = false, softSecond: Bool = false) -> HapticPattern {
            .init(steps: [.buzz(a, sharpness: softFirst ? 0.15 : 0.65), .rest(0.2), .buzz(b, sharpness: softSecond ? 0.15 : 0.65)])
        }
        func taps(_ count: Int, gaps: [Double] = [], sharpness: Double = 0.5) -> HapticPattern {
            var steps: [HapticStep] = []
            for i in 0..<count {
                steps.append(.tap(sharpness: sharpness))
                if i < count - 1 { steps.append(.rest(gaps.isEmpty ? 0.2 : gaps[i])) }
            }
            return .init(steps: steps)
        }
        func continuous(_ intensity: Double = 1, sharpness: Double = 0.5, envelope: Envelope = .flat) -> HapticPattern {
            .init(steps: [.buzz(0.7, intensity: intensity, sharpness: sharpness, envelope: envelope)])
        }
        func set(_ index: Int, _ code: String, _ name: String, _ detail: String, _ patterns: [HapticPattern]) -> PatternSet {
            PatternSet(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
                       name: name, code: code, detail: detail, isBuiltIn: true,
                       updatedAt: Date(timeIntervalSince1970: 0),
                       patterns: Dictionary(uniqueKeysWithValues: zip(Direction.allCases, patterns)))
        }
        return [
            set(1, "A", "길이 조합", "짧고 긴 진동의 순서로 방향을 구별해요.", [pair(0.1, 0.1), pair(0.35, 0.35), pair(0.35, 0.1), pair(0.1, 0.35)]),
            set(2, "B", "횟수", "앞 1회 · 뒤 4회 · 왼쪽 2회 · 오른쪽 3회.", [taps(1), taps(4), taps(2), taps(3)]),
            set(3, "C", "리듬 묶음", "같은 네 번의 탭을 다른 묶음으로 느껴보세요.", [taps(4, gaps: [0.2, 0.2, 0.2]), taps(4, gaps: [0.08, 0.44, 0.08]), taps(4, gaps: [0.08, 0.08, 0.44]), taps(4, gaps: [0.44, 0.08, 0.08])]),
            set(4, "D", "속도 변화", "빠르게 · 느리게 · 점점 빠르게 · 점점 느리게.", [taps(3, gaps: [0.12, 0.12]), taps(3, gaps: [0.5, 0.5]), taps(3, gaps: [0.5, 0.12]), taps(3, gaps: [0.12, 0.5])]),
            set(5, "E", "강도 변화", "커지고 작아지는 진동의 흐름을 비교해요.", [continuous(envelope: .rise), continuous(envelope: .fall), continuous(envelope: .hill), continuous(envelope: .valley)]),
            set(6, "F", "강도 단계", "길이는 같고 세기만 달라요. 휴대 위치의 영향도 확인하세요.", [continuous(0.3), continuous(0.5), continuous(0.75), continuous(1)]),
            set(7, "G", "촉감 단계", "둥근 느낌부터 날카로운 느낌까지 네 단계예요.", [continuous(sharpness: 0), continuous(sharpness: 0.33), continuous(sharpness: 0.67), continuous(sharpness: 1)]),
            set(8, "H", "복합", "길이와 촉감을 함께 사용해 방향의 차이를 강조해요.", [taps(2, sharpness: 1), continuous(sharpness: 0), pair(0.35, 0.1, softFirst: true), pair(0.1, 0.35, softSecond: true)])
        ]
    }()
}
