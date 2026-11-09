import XCTest
@testable import HearIAmCore

final class GuidanceReplayStrainTests: XCTestCase {
    private let path=[FloorPoint(0,0),FloorPoint(20,0)]
    private func walk(_ points: [(Double,Double)],status: (Int) -> GuidanceReplayStatus = {_ in .guiding}) -> GuidanceReplay {
        let samples=points.enumerated().map {i,p in
            GuidanceReplaySample(time:Double(i)*0.2,position:FloorPoint(p.0,p.1),heading:0,targetIndex:1,status:status(i))
        }
        return GuidanceReplay(duration:Double(points.count-1)*0.2,samples:samples)
    }

    func testWalkingOnThePathStaysGreen() {
        let replay=walk((0..<40).map {(Double($0)*0.2,0.1)})
        XCTAssertTrue(GuidanceReplayStrain.values(replay:replay,path:path).allSatisfy {$0<0.01})
    }

    func testStrayingTurnsOrangeGraduallyAndComesBack() {
        // On the path, 1.2 m off for 3 s, then back on for 6 s.
        let points=(0..<15).map {(Double($0)*0.2,0.0)}+(15..<30).map {(Double($0)*0.2,1.2)}+(30..<60).map {(Double($0)*0.2,0.0)}
        let values=GuidanceReplayStrain.values(replay:walk(points),path:path)
        XCTAssertLessThan(values[15],0.5,"eases in, not a jump")
        XCTAssertGreaterThan(values[29],0.9)
        XCTAssertLessThan(values[59],0.1,"back to green once on the path again")
    }

    func testPausedOffRouteCountsEvenWhenClose() {
        let replay=walk((0..<20).map {(Double($0)*0.2,0.2)},status:{$0>=5 ? .offRoute : .guiding})
        XCTAssertGreaterThan(GuidanceReplayStrain.values(replay:replay,path:path).last!,0.9)
    }

    func testStandingStillAwayFromPointsStrainsButAtAPointDoesNot() {
        let away=walk(Array(repeating:(5.0,0.0),count:30))
        XCTAssertGreaterThan(GuidanceReplayStrain.values(replay:away,path:path).last!,0.4)
        let atPoint=walk(Array(repeating:(20.0,0.0),count:30))
        XCTAssertLessThan(GuidanceReplayStrain.values(replay:atPoint,path:path).last!,0.01)
        let heldPause=walk(Array(repeating:(5.0,0.0),count:30),status:{_ in .paused})
        XCTAssertLessThan(GuidanceReplayStrain.values(replay:heldPause,path:path).last!,0.01)
    }
}
