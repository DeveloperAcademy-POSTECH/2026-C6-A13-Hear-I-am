import XCTest
@testable import HearIAmCore

final class SideLandmarkTests: XCTestCase {
    func obstacle(_ name: String="책장", x: Double = -1, y: Double=3, width: Double=0.5, length: Double=3) throws -> StageObstacle {
        try StageObstacle(name:name,kind:.box,vertices:[.init(x,y),.init(x+width,y),.init(x+width,y+length),.init(x,y+length)])
    }
    func walk(_ gate: inout SideLandmarkGate, objects: [StageObstacle]) {
        for i in 0...8 { gate.observe(time:Double(i)*0.1,position:.init(0,5-Double(i)*0.03),heading:0,obstacles:objects) }
    }
    func testRightAndLeftNearestNamesWhileWalking() throws {
        let right=try obstacle(), left=try obstacle("책상",x:0.6), further=try obstacle("먼 책장",x:-1.5)
        var gate=SideLandmarkGate();walk(&gate,objects:[further,left,right])
        let items=gate.candidates(position:.init(0,4.76),heading:0,obstacles:[further,left,right])
        XCTAssertEqual(items.map(\.line),["오른쪽 책장","왼쪽 책상"])
    }
    func testNoSideSpeechForStationaryJitterOrRotation() throws {
        let objects=[try obstacle()]
        for rotating in [false,true] {
            var gate=SideLandmarkGate()
            for i in 0...30 {
                gate.observe(time:Double(i)*0.1,position:.init(Double(i%2)*0.02,5),heading:rotating ? Double(i)*10 : 0,obstacles:objects)
                XCTAssertTrue(gate.candidates(position:.init(0,5),heading:0,obstacles:objects).isEmpty)
            }
        }
    }
    func testMotionExpiresWhenStoppedOrInputIsInvalid() throws {
        let objects=[try obstacle()];var gate=SideLandmarkGate();walk(&gate,objects:objects)
        XCTAssertTrue(gate.isMoving)
        for t in [0.9,1.0,1.1,1.2] { gate.observe(time:t,position:.init(0,4.76),heading:0,obstacles:objects) }
        XCTAssertFalse(gate.isMoving)
        walk(&gate,objects:objects)
        gate.observe(time:2,position:.init(0,4.76),heading:0,obstacles:objects)
        XCTAssertFalse(gate.isMoving)
        gate.observe(time:2.1,position:.init(.nan,4),heading:0,obstacles:objects)
        XCTAssertFalse(gate.isMoving)
    }
    func testForwardBehindFarAndUnsafeObjectsAreNotLandmarks() throws {
        let objects=[try obstacle("앞",x:-0.2,y:3,width:0.4,length:0.3),
                     try obstacle("뒤",x:-0.2,y:5.8,width:0.4,length:0.3),
                     try obstacle("멀리",x:-3),try obstacle("너무 가까움",x:-0.3,width:0.1)]
        var gate=SideLandmarkGate();walk(&gate,objects:objects)
        XCTAssertTrue(gate.candidates(position:.init(0,4.76),heading:0,obstacles:objects).isEmpty)
    }
    func testLongObjectUsesBoundaryAndSpeaksOnceWhilePassing() throws {
        let object=try obstacle(y:-20,length:30);var gate=SideLandmarkGate();walk(&gate,objects:[object])
        let items=gate.candidates(position:.init(0,4.76),heading:0,obstacles:[object])
        XCTAssertEqual(items.count,1)
        gate.didSpeak(items)
        for i in 9...40 { gate.observe(time:Double(i)*0.1,position:.init(0,5-Double(i)*0.03),heading:0,obstacles:[object]) }
        XCTAssertTrue(gate.candidates(position:.init(0,3.8),heading:0,obstacles:[object]).isEmpty)
    }
    func testEncounterRearmsAfterLeavingThenReturning() throws {
        let objects=[try obstacle()];var gate=SideLandmarkGate();walk(&gate,objects:objects)
        gate.didSpeak(gate.candidates(position:.init(0,4.76),heading:0,obstacles:objects))
        gate.observe(time:2,position:.init(0,0),heading:0,obstacles:objects)
        for i in 0...8 { gate.observe(time:3+Double(i)*0.1,position:.init(0,4+Double(i)*0.03),heading:180,obstacles:objects) }
        XCTAssertEqual(gate.candidates(position:.init(0,4.24),heading:180,obstacles:objects).map(\.line),["왼쪽 책장"])
    }
    func testAlreadyPassedLandmarkIsNotQueuedAndActiveCueExpires() throws {
        let objects=[try obstacle(y:4.5,length:0.5)]
        var gate=SideLandmarkGate();walk(&gate,objects:objects)
        let old=gate.candidates(position:.init(0,4.76),heading:0,obstacles:objects)
        XCTAssertFalse(old.isEmpty)
        XCTAssertFalse(SideLandmarkGate.stillBeside(old,position:.init(0,3.0),heading:0,obstacles:objects))
        XCTAssertTrue(gate.candidates(position:.init(0,3),heading:0,obstacles:objects).isEmpty)
    }
}
