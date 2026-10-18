import XCTest
@testable import HearIAmCore

/// #38: the clearance a route keeps from blocking objects is computed once and both drawn and enforced.
final class ObstacleClearanceTests: XCTestCase {
    let box=[Point3(1,0,-1),Point3(2,0,-1),Point3(2,0,-3),Point3(1,0,-3)]
    func draft(_ kind: ObstacleKind = .box) throws -> PreparationDraft {
        var d=PreparationDraft()
        d.corners=PerformancePlan.area.corners.map { Optional($0) }
        d.objects=[WorldObstacle(name:kind == .box ? "상자" : "단상",kind:kind,vertices:box)]
        try d.addRoutePoint(Point3(-1,0,-2))
        return d
    }
    func testPointInsideClearanceIsRefusedWithTheObjectAndOverlap() throws {
        var d=try draft()
        let hit=try XCTUnwrap(d.clearanceHit(adding:Point3(0.9,0,-2)))
        XCTAssertEqual(hit.name,"상자");XCTAssertTrue(hit.pointInside);XCTAssertEqual(hit.overlap,0.05,accuracy:1e-9)
        XCTAssertEqual(hit.message,"십자선이 상자 여유 영역 안이에요 · 5cm 겹침")
        XCTAssertThrowsError(try d.addRoutePoint(Point3(0.9,0,-2)))
        XCTAssertNil(d.clearanceHit(adding:Point3(0.8,0,-2)))
        XCTAssertEqual(d.route.count,1)
    }
    func testSegmentThroughTheObjectIsRefusedEvenWhenThePointIsClear() throws {
        var d=try draft()
        let hit=try XCTUnwrap(d.clearanceHit(adding:Point3(3.5,0,-2)))
        XCTAssertFalse(hit.pointInside);XCTAssertEqual(hit.overlap,PreparationDraft.obstacleClearance,accuracy:1e-9)
        XCTAssertThrowsError(try d.addRoutePoint(Point3(3.5,0,-2),asDestination:false))
    }
    func testPointsOutsideTheClearanceAndPlatformsAreAccepted() throws {
        var d=try draft()
        XCTAssertNil(d.clearanceHit(adding:Point3(0.5,0,-2)))
        try d.addRoutePoint(Point3(0.5,0,-2))
        var platform=try draft(.platform)
        XCTAssertNil(platform.clearanceHit(adding:Point3(3.5,0,-2)))
        try platform.addRoutePoint(Point3(3.5,0,-2))
    }
    func testRefusalMatchesTheRouteCheck() throws {
        // Whatever clearanceHit lets through must not be reported later by routeErrors, and the reverse.
        let d=try draft()
        for x in stride(from:-0.5,through:4.0,by:0.05) {
            var next=d;next.route.append(Point3(x,0,-2))
            let refused=d.clearanceHit(adding:Point3(x,0,-2)) != nil
            let segment=try XCTUnwrap(next.objects.first).projected(in:XCTUnwrap(next.area))
            let conflict=segment.overlaps(next.area!.floor(next.route[0]),next.area!.floor(next.route[1]),clearance:PreparationDraft.obstacleClearance)
            XCTAssertEqual(refused,conflict,"x=\(x)")
        }
    }
    func testClearanceCellsCoverTheGrownOutline() throws {
        let square=try StageObstacle(name:"상자",kind:.box,vertices:[.init(0,0),.init(1,0),.init(1,1),.init(0,1)])
        let cell=0.05, clearance=0.35
        let cells=square.clearanceCells(clearance:clearance,cell:cell)
        let expected=1+4*clearance+Double.pi*clearance*clearance
        XCTAssertEqual(Double(cells.count)*cell*cell,expected,accuracy:expected*0.03)
        XCTAssertTrue(cells.allSatisfy { square.distance(to:$0) <= clearance })
        XCTAssertTrue(square.clearanceCells(clearance:clearance,cell:0).isEmpty)
    }
    func testStagesSavedWithTheOldClearanceUseTheCurrentOne() throws {
        let a=PerformancePlan.area
        var old=GuideSettings();old.obstacleClearance=0.35
        let m=ScanManifest(id:UUID(),name:"무대",frame:try StageFrame(origin:a.world(FloorPoint(0,0)),front:a.world(FloorPoint(0,-1))),
                           checkpoint:a.corners[2],worldMapHash:"",meshHash:"",meshCount:1,vertexCount:3,device:"",appVersion:"",settings:old)
        let decoded=try JSONDecoder().decode(ScanManifest.self,from:JSONEncoder().encode(m))
        XCTAssertEqual(decoded.settings.obstacleClearance,GuideSettings.routeClearance)
        XCTAssertEqual(GuideSettings().obstacleClearance,0.15)
    }
}
