import XCTest
@testable import HearIAmCore

/// Adding or duplicating a point in the route editor keeps the later points' holds (#179).
final class PlanInsertPointTests: XCTestCase {
    private func route(holdAt index: Int, seconds: Int) throws -> PerformancePlan {
        var plan=PerformancePlan();plan.isReferenceOnly=true
        for x in [1.0,3,5,7] {try plan.append(FloorPoint(x,2))}
        plan.completeReference()
        try plan.setPointSettings(.init(name:"",holdSeconds:seconds),at:index)
        return plan
    }

    func testAddingBeforeTheEndKeepsTheHoldOfThePointBefore() throws {
        var plan=try route(holdAt:2,seconds:10)
        try plan.insertPoint(FloorPoint(6,4),at:3)
        XCTAssertEqual(plan.points.count,5)
        XCTAssertEqual(plan.settings(at:2).holdSeconds,10)
        XCTAssertEqual(plan.points[3],FloorPoint(6,4))
        XCTAssertEqual(plan.points[4],FloorPoint(7,2))
        XCTAssertTrue(plan.finished)
    }

    func testDuplicatingBeforeAHoldingPointMovesItsHoldAlong() throws {
        var plan=try route(holdAt:2,seconds:10)
        try plan.insertPoint(FloorPoint(1.4,2.4),at:1)
        XCTAssertEqual(plan.settings(at:3).holdSeconds,10)
        XCTAssertEqual(plan.points[3],FloorPoint(5,2))
        XCTAssertEqual(plan.settings(at:1).holdSeconds,0)
    }

    func testRefusesTheSameSpotAsANeighbour() throws {
        var plan=try route(holdAt:1,seconds:5)
        XCTAssertThrowsError(try plan.insertPoint(FloorPoint(3,2),at:2))
        XCTAssertThrowsError(try plan.insertPoint(FloorPoint(5.01,2),at:2))
        XCTAssertEqual(plan.points.count,4)
    }

    func testRefusesOutsideTheCanvasAndPastTheLimit() throws {
        var plan=try route(holdAt:1,seconds:5)
        XCTAssertThrowsError(try plan.insertPoint(FloorPoint(20,2),at:2))
        XCTAssertThrowsError(try plan.insertPoint(FloorPoint(2,2),at:9))
    }
}
