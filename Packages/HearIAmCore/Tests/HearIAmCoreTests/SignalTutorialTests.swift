import XCTest
@testable import HearIAmCore

final class SignalTutorialTests: XCTestCase {
    func testEveryOriginalPreviewHasExactlyOneDestination() {
        // Frozen inventory from develop 7e7aa64, including louder next-side speech and both completion previews.
        let expected: [String:SignalTutorialPlayback] = [
            "ready-ding":.arrival, "tick-left":.directionTick(toRight:false), "tick-right":.directionTick(toRight:true),
            "aligned":.aligned, "start":.speech("출발"), "point-1":.speech("피일"), "point-2":.speech("피이"),
            "point-chair":.speech("의자일"), "point-stairs":.speech("계단일"),
            "completion":.completion, "completed-voice":.speech("마지막 지점 도착"),
            "next-left":.nextSide("왼쪽"), "next-right":.nextSide("오른쪽"),
            "correct-left":.speech("왼쪽"), "correct-right":.speech("오른쪽"),
            "hint-chair":.speech("의자"), "hint-stairs":.speech("계단"),
            "distance-300":.speech("3미터"), "distance-200":.speech("2미터"),
            "distance-100":.speech("1미터"), "distance-50":.speech("50센티"),
            "look-left":.speech("왼쪽 봐"), "look-right":.speech("오른쪽 봐")
        ]
        let all=SignalTutorialStep.allCases.flatMap { $0.groups.flatMap(\.examples) }
        XCTAssertEqual(all.count,23)
        XCTAssertEqual(Set(all.map(\.id)).count,all.count)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues:all.map {($0.id,$0.playback)}),expected)
    }

    func testDirectEntryCanNavigateBothWaysWithoutWrapping() {
        var step=SignalTutorialStep.alignment
        XCTAssertEqual(step.rawValue,3)
        XCTAssertEqual(step.previous,.direction)
        XCTAssertEqual(step.next,.arrival)
        while let next=step.next { step=next }
        XCTAssertEqual(step,.objects)
        XCTAssertNil(step.next)
        while let previous=step.previous { step=previous }
        XCTAssertEqual(step,.preparation)
        XCTAssertNil(step.previous)
    }

    func testCatalogUsesCurrentSharedVoiceCopy() {
        let voices=SignalTutorialStep.allCases.flatMap { $0.groups.flatMap(\.examples) }.compactMap { item -> String? in
            if case .speech(let line)=item.playback {return line};return nil
        }
        for line in [SignalCopy.start,SignalCopy.point(1),SignalCopy.point(2),GuidanceCopy.completed,
                     SignalCopy.distance(0.5),SignalCopy.stepPoint(stairs:true,number:1),SignalCopy.look(toRight:true)] {
            XCTAssertTrue(voices.contains(line),line)
        }
    }
}
