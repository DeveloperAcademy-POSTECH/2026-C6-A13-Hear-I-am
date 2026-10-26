import XCTest
@testable import HearIAmCore

final class StagePlanReferenceTests: XCTestCase {
    func plan() throws -> PerformancePlan {
        var p=PerformancePlan()
        try p.append(.init(-1,2)); try p.append(.init(6,4)); try p.append(.init(13,6))
        try p.addObject(at:.init(3,6),platform:true)
        try p.finishRoute()
        return p
    }
    func testReferenceFitsDifferentAspectRatioIncludingOutsideEndpointsAndObjectOutline() throws {
        let p=try plan()
        let area=try StageArea(corners:[.init(0,0,0),.init(6,0,0),.init(6,0,-16),.init(0,0,-16)])
        let ref=try StagePlanReference(plan:p,area:area)
        XCTAssertEqual(ref.points,[.init(-0.5,4),.init(3,8),.init(6.5,12)])
        let vertices=try XCTUnwrap(ref.objects.first).vertices
        XCTAssertEqual(vertices.count,4)
        XCTAssertEqual(vertices[0].x,1.2,accuracy:1e-9)
        XCTAssertEqual(vertices[0].y,11,accuracy:1e-9)
        XCTAssertEqual(vertices[2].x,1.8,accuracy:1e-9)
        XCTAssertEqual(vertices[2].y,13,accuracy:1e-9)
        XCTAssertEqual(p.points[1],.init(6,4))
    }
    func testReferenceUsesCapturedStageOrientationAndHeight() throws {
        let area=try StageArea(corners:[.init(10,1,20),.init(10,1,26),.init(14,1,26),.init(14,1,20)])
        let ref=try StagePlanReference(plan:plan(),area:area)
        let world=area.world(ref.points[1])
        XCTAssertEqual(world.x,12,accuracy:1e-9)
        XCTAssertEqual(world.y,1,accuracy:1e-9)
        XCTAssertEqual(world.z,23,accuracy:1e-9)
    }
    func testLoadingReferenceDoesNotRegisterAnythingOrPermitSaving() throws {
        var draft=PreparationDraft()
        draft.corners=PerformancePlan.area.corners.map(Optional.some)
        let reference=try draft.reference(for:plan())
        XCTAssertEqual(reference.points.count,3); XCTAssertEqual(reference.objects.count,1)
        XCTAssertTrue(draft.route.isEmpty); XCTAssertTrue(draft.objects.isEmpty)
        XCTAssertFalse(draft.routeFinished); XCTAssertFalse(draft.planApplied)
        XCTAssertEqual(draft.effectiveObstacleClearance,PreparationDraft.obstacleClearance)
        XCTAssertThrowsError(try draft.stageRoute())
        XCTAssertFalse(draft.errors.isEmpty)
    }
    func testChangingRectangleReprojectsReferenceWithoutMovingManualPointsOrMutatingPlan() throws {
        let p=try plan(), encoded=try JSONEncoder().encode(p)
        var draft=PreparationDraft()
        draft.corners=PerformancePlan.area.corners.map(Optional.some)
        try draft.addRoutePoint(.init(-1,0,-2)); try draft.addRoutePoint(.init(2,0,-2))
        try draft.addRoutePoint(.init(13,0,-2),asDestination:true)
        draft.checkpoint = .init(5,0,-5)
        let route=draft.route, checkpoint=draft.checkpoint
        let first=try draft.reference(for:p)
        XCTAssertTrue(draft.routeFinished)
        draft.corners=[.init(0,0,0),.init(6,0,0),.init(6,0,-4),.init(0,0,-4)]
        let second=try draft.reference(for:p)
        XCTAssertEqual(first.points[1],.init(6,4))
        XCTAssertEqual(second.points[1],.init(3,2))
        XCTAssertEqual(draft.route,route); XCTAssertEqual(draft.checkpoint,checkpoint)
        XCTAssertEqual(try JSONDecoder().decode(PerformancePlan.self,from:encoded),p)
    }
    func testMissingRectangleAndIncompletePlanAreRejected() throws {
        XCTAssertThrowsError(try PreparationDraft().reference(for:plan()))
        XCTAssertThrowsError(try StagePlanReference(plan:PerformancePlan(),area:PerformancePlan.area))
    }
}
