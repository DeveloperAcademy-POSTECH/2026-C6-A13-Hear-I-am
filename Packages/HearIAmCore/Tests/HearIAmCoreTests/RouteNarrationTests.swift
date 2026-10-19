import XCTest
@testable import HearIAmCore

final class RouteNarrationTests: XCTestCase {
    func obstacle(_ name: String="책장", x: Double = -1, y: Double=3, width: Double=0.5, length: Double=3) throws -> StageObstacle {
        try StageObstacle(name:name,kind:.box,vertices:[.init(x,y),.init(x+width,y),.init(x+width,y+length),.init(x,y+length)])
    }
    func walk(_ gate: inout SideLandmarkGate, objects: [StageObstacle]) {
        for i in 0...8 { gate.observe(time:Double(i)*0.1,position:.init(0,5-Double(i)*0.03),heading:0,obstacles:objects) }
    }
    func testNarrationWaitsForAlignmentAndCooldownThenUsesLatestDistance() throws {
        var gate=RouteNarrationGate()
        gate.observe(targetIndex:1,time:0,position:.init(0,5),heading:0,obstacles:[])
        XCTAssertNil(gate.candidate(time:0,meters:3.2,eligible:false,position:.init(0,5),heading:0,obstacles:[]))
        let first=try XCTUnwrap(gate.candidate(time:1,meters:3.2,eligible:true,position:.init(0,5),heading:0,obstacles:[]))
        XCTAssertEqual(first.line,"삼점이");gate.didSpeak(first,time:1)
        XCTAssertNil(gate.candidate(time:1.5,meters:1.2,eligible:true,position:.init(0,3),heading:0,obstacles:[]))
        XCTAssertEqual(gate.candidate(time:2.5,meters:0.7,eligible:true,position:.init(0,2.5),heading:0,obstacles:[])?.line,"영점칠")
    }
    func testResumePreservesDistanceAndNewTargetRearmsIt() throws {
        var gate=RouteNarrationGate()
        gate.observe(targetIndex:1,time:0,position:.init(0,5),heading:0,obstacles:[])
        let first=try XCTUnwrap(gate.candidate(time:0,meters:3.2,eligible:true,position:.init(0,5),heading:0,obstacles:[]))
        gate.didSpeak(first,time:0);gate.suspendMotion()
        gate.observe(targetIndex:1,time:5,position:.init(0,5),heading:0,obstacles:[])
        XCTAssertNil(gate.candidate(time:5,meters:3.2,eligible:true,position:.init(0,5),heading:0,obstacles:[]))
        gate.observe(targetIndex:2,time:6,position:.init(0,5),heading:0,obstacles:[])
        XCTAssertEqual(gate.candidate(time:6,meters:3.2,eligible:true,position:.init(0,5),heading:0,obstacles:[])?.line,"삼점이")
    }
    func testFirstDistanceThenLandmarkThenFreshDistance() throws {
        let objects=[try obstacle()];var gate=RouteNarrationGate()
        for i in 0...8 { gate.observe(targetIndex:1,time:Double(i)*0.1,position:.init(0,5-Double(i)*0.03),heading:0,obstacles:objects) }
        let first=try XCTUnwrap(gate.candidate(time:0.8,meters:4,eligible:true,position:.init(0,4.76),heading:0,obstacles:objects))
        XCTAssertEqual(first.line,"사");gate.didSpeak(first,time:0.8)
        for i in 9...25 { gate.observe(targetIndex:1,time:Double(i)*0.1,position:.init(0,5-Double(i)*0.03),heading:0,obstacles:objects) }
        XCTAssertNil(gate.candidate(time:2.5,meters:2,eligible:false,position:.init(0,4.25),heading:0,obstacles:objects))
        let side=try XCTUnwrap(gate.candidate(time:2.5,meters:2,eligible:true,position:.init(0,4.25),heading:0,obstacles:objects))
        XCTAssertEqual(side.line,"오른쪽 책장");gate.didSpeak(side,time:2.5)
        XCTAssertEqual(gate.candidate(time:4,meters:1.5,eligible:true,position:.init(0,3),heading:0,obstacles:objects)?.line,"일점오")
    }
    func testCompactPlatformCueRetainsDescentAndStairs() {
        func cue(_ kind: StepCue.Kind, stairs: Bool=false) -> StepCue {
            StepCue(kind:kind,stairs:stairs,obstacleID:UUID(),name:"기물",distance:0.7)
        }
        XCTAssertEqual(cue(.up).guidanceLine,"단상 접근")
        XCTAssertEqual(cue(.down).guidanceLine,"내려갑니다")
        XCTAssertEqual(cue(.over).guidanceLine,"단상 접근. 바로 내려감.")
        XCTAssertEqual(cue(.up,stairs:true).guidanceLine,cue(.up,stairs:true).line)
    }
}
