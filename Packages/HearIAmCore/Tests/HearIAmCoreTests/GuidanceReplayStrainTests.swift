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

    func testWalkingSidewaysOrBackTurnsOrangeEvenOnThePath() {
        // Along the leg for 3 s, then straight back toward the start for 3 s, still exactly on the path line.
        let back=(0..<15).map {(Double($0)*0.2,0.0)}+(1...15).map {(2.8-Double($0)*0.2,0.0)}
        let values=GuidanceReplayStrain.values(replay:walk(back),path:path)
        XCTAssertLessThan(values[14],0.01)
        XCTAssertGreaterThan(values.last!,0.9,"walking away from the next point is the wrong way")
        // Crossing the corridor sideways, within the free distance of the path.
        let across=(0..<10).map {(Double($0)*0.2,0.0)}+(1...6).map {(1.8,-0.3+Double($0)*0.1)}
        XCTAssertGreaterThan(GuidanceReplayStrain.values(replay:walk(across),path:path).last!,0.4)
    }

    func testTurningBackAndForthReadsAsSearching() {
        let zigzag=(0..<10).map {(Double($0)*0.2,0.0)}+(0..<20).map {(1.8+($0.isMultiple(of:2) ? 0.0 : 0.3),0.0)}
        XCTAssertGreaterThan(GuidanceReplayStrain.values(replay:walk(zigzag),path:path).last!,0.6)
    }

    func testAnotherPartOfTheRouteIsNotTheCurrentLeg() {
        // Target is point 1 of an L-shaped route, but the person walks along the second leg.
        let route=[FloorPoint(0,0),FloorPoint(10,0),FloorPoint(10,10)]
        let samples=(0..<30).map {i in
            GuidanceReplaySample(time:Double(i)*0.2,position:FloorPoint(10,1+Double(i)*0.2),heading:0,targetIndex:1,status:.guiding)
        }
        let values=GuidanceReplayStrain.values(replay:GuidanceReplay(duration:5.8,samples:samples),path:route)
        XCTAssertGreaterThan(values.last!,0.9)
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
