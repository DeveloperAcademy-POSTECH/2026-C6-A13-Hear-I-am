import XCTest
@testable import HearIAmCore

final class PlatformEdgesTests: XCTestCase {
    func object(entry: [Int]? = [3], exit: [Int]? = [1]) throws -> StageObstacle {
        try StageObstacle(name:"단상",kind:.platform,passage:.passable,
            vertices:[.init(2,2),.init(4,2),.init(4,4),.init(2,4)],height:0.4,entryEdges:entry,exitEdges:exit)
    }
    func testDirectionalCrossingsAndClosedSides() throws {
        let o=try object()
        XCTAssertFalse(o.blocksTravel(from:.init(1,3),to:.init(3,3),clearance:0.1))
        XCTAssertFalse(o.blocksTravel(from:.init(3,3),to:.init(5,3),clearance:0.1))
        XCTAssertFalse(o.blocksTravel(from:.init(1,3),to:.init(5,3),clearance:0.1))
        XCTAssertTrue(o.blocksTravel(from:.init(5,3),to:.init(1,3),clearance:0.1))
        XCTAssertTrue(o.blocksTravel(from:.init(3,1),to:.init(3,3),clearance:0.1))
        XCTAssertTrue(o.blocksTravel(from:.init(1,1.95),to:.init(5,1.95),clearance:0.1))
        XCTAssertFalse(o.blocksTravel(from:.init(2.5,3),to:.init(3.5,3),clearance:0.1))
    }
    func testMultipleEdgesBidirectionalAndRoundTrip() throws {
        let o=try object(entry:[0,1,3],exit:[1,3])
        let decoded=try JSONDecoder().decode(StageObstacle.self,from:JSONEncoder().encode(o))
        XCTAssertEqual(o,decoded)
        XCTAssertFalse(decoded.blocksTravel(from:.init(5,3),to:.init(1,3),clearance:0.1))
        XCTAssertFalse(decoded.blocksTravel(from:.init(3,1),to:.init(3,3),clearance:0.1))
        XCTAssertTrue(decoded.blocksTravel(from:.init(3,3),to:.init(3,1),clearance:0.1))
    }
    func testLegacyAndInvalidEdges() throws {
        let old=try object(entry:nil,exit:nil)
        let decoded=try JSONDecoder().decode(StageObstacle.self,from:JSONEncoder().encode(old))
        XCTAssertFalse(decoded.blocksTravel(from:.init(1,3),to:.init(5,3),clearance:0.1))
        XCTAssertThrowsError(try object(entry:[4]))
        XCTAssertThrowsError(try object(entry:[1,1]))
        XCTAssertTrue(try object(entry:[],exit:[]).blocksTravel(from:.init(1,3),to:.init(5,3),clearance:0))
    }
    func testClockwiseOutlineAndCornerCannotBypassClosedSide() throws {
        var o=try object()
        o.vertices.reverse(); o.entryEdges=[3]; o.exitEdges=[1]
        XCTAssertFalse(o.blocksTravel(from:.init(1,3),to:.init(5,3),clearance:0.1))
        XCTAssertTrue(o.blocksTravel(from:.init(1,1),to:.init(3,3),clearance:0))
    }
    func testClosedSideWarningsAndLiveGuidance() throws {
        let o=try object()
        var warning=WarningGate()
        XCTAssertNotNil(warning.update(position:.init(3,1.8),headingDegrees:0,obstacles:[o]))
        warning.reset()
        XCTAssertNil(warning.update(position:.init(1.8,3),headingDegrees:0,obstacles:[o]))
        let area=try StageArea(corners:[Point3(6,0,0),Point3(0,0,0),Point3(0,0,6),Point3(6,0,6)])
        let route=try StageRoute(area:area,points:[.init(1,3),.init(3,3),.init(5,3)],obstacles:[o])
        var settings=GuideSettings(); settings.obstacleClearance=0.1
        var guide=RouteGuide(route:route,settings:settings,usesRouteCorridor:true)
        XCTAssertTrue(guide.start(position:.init(1,3),headingDegrees:0,trackingValid:true))
        XCTAssertNil(guide.positionIssue(.init(2.5,3)))
        XCTAssertEqual(guide.positionIssue(.init(3,1.95)),.offRoute)
        _=guide.observe(time:0,position:.init(2.5,3),headingDegrees:0,trackingValid:true,allowsTargetAdvance:false)
        // Leaving through the entry-only edge must not be accepted even within the route corridor.
        let result=guide.observe(time:0.1,position:.init(1.9,3),headingDegrees:0,trackingValid:true)
        XCTAssertEqual(result.state,.paused)
        XCTAssertEqual(guide.pauseReason,.obstacleProximity)
    }
    func testConcaveOutlineChecksEveryCrossing() throws {
        let o=try StageObstacle(name:"오목 단상",kind:.platform,passage:.passable,
            vertices:[.init(1,1),.init(5,1),.init(5,5),.init(4,5),.init(4,2),.init(2,2),.init(2,5),.init(1,5)],
            entryEdges:[7],exitEdges:[1])
        // Endpoints are inside separate arms, but the path crosses two closed inner sides.
        XCTAssertTrue(o.blocksTravel(from:.init(1.5,4),to:.init(4.5,4),clearance:0))
    }
    func testConfirmedHeightCanBeSavedButDoesNotBypassGeometry() throws {
        var draft=PreparationDraft()
        draft.corners=[Point3(6,0,0),Point3(0,0,0),Point3(0,0,6),Point3(6,0,6)].map(Optional.some)
        let area=try XCTUnwrap(draft.area)
        let shape=try object()
        draft.objects=[WorldObstacle(name:"단상",kind:.platform,vertices:shape.vertices.map(area.world),height:0.3,entryEdges:[3],exitEdges:[1])]
        try draft.addRoutePoint(area.world(.init(1,3)))
        var top=area.world(.init(3,3)); top.y=0.6
        XCTAssertThrowsError(try draft.addRoutePoint(top))
        XCTAssertEqual(draft.route.count,1)
        try draft.addRoutePoint(top,confirmHeightMismatch:true)
        try draft.addRoutePoint(area.world(.init(5,3)),asDestination:true)
        let saved=try draft.stageRoute()
        XCTAssertTrue(draft.routeErrors.isEmpty)
        let decoded=try JSONDecoder().decode(StageRoute.self,from:JSONEncoder().encode(saved))
        XCTAssertEqual(decoded.pointHeights,[0,0.6,0])
        draft.removeLastRoutePoint(); draft.removeLastRoutePoint()
        XCTAssertThrowsError(try draft.addRoutePoint(top))
        var outside=area.world(.init(1,1)); outside.y=0.6
        XCTAssertThrowsError(try draft.addRoutePoint(outside,confirmHeightMismatch:true))
        var invalid=top; invalid.y=3
        XCTAssertThrowsError(try draft.addRoutePoint(invalid,confirmHeightMismatch:true))
        draft.objects[0].entryEdges=[]
        XCTAssertThrowsError(try draft.addRoutePoint(top,confirmHeightMismatch:true))
    }
    func testCheckpointAllowsBoundaryBandButNotObjectInterior() throws {
        var draft=PreparationDraft()
        draft.corners=[Point3(6,0,0),Point3(0,0,0),Point3(0,0,6),Point3(6,0,6)].map(Optional.some)
        let area=try XCTUnwrap(draft.area), shape=try object()
        for kind in [ObstacleKind.other,.box,.platform,.stairs] {
            draft.objects=[WorldObstacle(name:"기물",kind:kind,vertices:shape.vertices.map(area.world),height:0.5)]
            for point in [FloorPoint(1.9,3),.init(2,3),.init(2.049,3),.init(2.05,3),.init(2,2)] {
                draft.checkpoint=area.world(point)
                XCTAssertTrue(draft.checkpointErrors.isEmpty,"\(kind): \(point)")
            }
            for point in [FloorPoint(2.051,3),.init(3,3)] {
                draft.checkpoint=area.world(point)
                XCTAssertFalse(draft.checkpointErrors.isEmpty)
            }
            var top=area.world(.init(2,3)); top.y=0.5
            draft.checkpoint=top
            XCTAssertFalse(draft.checkpointErrors.isEmpty)
        }
        // A point near one outline may still be deep inside another object.
        draft.objects.append(WorldObstacle(name:"겹친 기물",kind:.other,
            vertices:[FloorPoint(1,1),.init(5,1),.init(5,5),.init(1,5)].map(area.world)))
        draft.checkpoint=area.world(.init(2,3))
        XCTAssertFalse(draft.checkpointErrors.isEmpty)
        draft.objects=[]
        draft.checkpoint=area.corners[0]
        XCTAssertFalse(draft.checkpointErrors.isEmpty)
    }
    func testBoundaryDistanceForConcaveAndReversedOutline() throws {
        var shape=try StageObstacle(name:"오목",kind:.other,
            vertices:[.init(1,1),.init(5,1),.init(5,5),.init(4,5),.init(4,2),.init(2,2),.init(2,5),.init(1,5)])
        for _ in 0..<2 {
            XCTAssertTrue(shape.contains(.init(1.96,3)))
            XCTAssertEqual(shape.boundaryDistance(to:.init(1.96,3)),0.04,accuracy:1e-9)
            XCTAssertEqual(shape.boundaryDistance(to:.init(1.5,3)),0.5,accuracy:1e-9)
            shape.vertices.reverse()
        }
    }
    func testHeightConfirmationCannotBypassStageMarginOrDangerZone() throws {
        var draft=PreparationDraft()
        draft.corners=[Point3(6,0,0),Point3(0,0,0),Point3(0,0,6),Point3(6,0,6)].map(Optional.some)
        let area=try XCTUnwrap(draft.area)
        draft.objects=[WorldObstacle(name:"의자",kind:.platform,
            vertices:[FloorPoint(0,2),.init(2,2),.init(2,4),.init(0,4)].map(area.world),height:0.3)]
        try draft.addRoutePoint(area.world(.init(3,3)))
        var point=area.world(.init(0.1,3)); point.y=0.6
        XCTAssertNotNil(draft.edgeIssue(adding:point))
        XCTAssertThrowsError(try draft.addRoutePoint(point,confirmHeightMismatch:true))
        XCTAssertEqual(draft.route.count,1)
        point=area.world(.init(0.6,3)); point.y=0.6
        XCTAssertNil(draft.edgeIssue(adding:point))
        draft.dangerZones=[StageDangerZone(edge:.left,distance:.halfMetre)]
        XCTAssertNotNil(draft.edgeIssue(adding:point))
        XCTAssertThrowsError(try draft.addRoutePoint(point,confirmHeightMismatch:true))
        XCTAssertEqual(draft.route.count,1)
    }
    func testObservedSurfaceMustMatchMeasuredHeight() throws {
        var draft=PreparationDraft()
        draft.corners=[Point3(6,0,0),Point3(0,0,0),Point3(0,0,6),Point3(6,0,6)].map(Optional.some)
        let area=try XCTUnwrap(draft.area)
        let shape=try object()
        draft.objects=[WorldObstacle(name:"단상",kind:.platform,vertices:shape.vertices.map(area.world),height:0.03)]
        var top=area.world(.init(3,3)); top.y=0.6
        XCTAssertTrue(try XCTUnwrap(draft.routeSurfaceError(top,in:area)).contains("±15cm"))
        XCTAssertThrowsError(try draft.addRoutePoint(top))
        draft.objects[0].height=0.45
        XCTAssertNil(draft.routeSurfaceError(top,in:area))
        top.y=0.601
        XCTAssertNotNil(draft.routeSurfaceError(top,in:area))
        top.y=0.30
        XCTAssertNil(draft.routeSurfaceError(top,in:area))
        top.y=0.299
        XCTAssertNotNil(draft.routeSurfaceError(top,in:area))
        var outside=area.world(.init(1,1)); outside.y=0.6
        XCTAssertTrue(try XCTUnwrap(draft.routeSurfaceError(outside,in:area)).contains("둘레 밖"))
        draft.objects[0].kind = .other
        XCTAssertNotNil(draft.routeSurfaceError(top,in:area))
        top.y = -0.5
        XCTAssertTrue(try XCTUnwrap(draft.routeSurfaceError(top,in:area)).contains("낮아요"))
    }
    func testRaisedPointAndWrongSidePlacement() throws {
        var draft=PreparationDraft()
        draft.corners=[Point3(6,0,0),Point3(0,0,0),Point3(0,0,6),Point3(6,0,6)].map(Optional.some)
        let a=try XCTUnwrap(draft.area)
        let o=try object()
        draft.objects=[WorldObstacle(name:o.name,kind:o.kind,vertices:o.vertices.map(a.world),height:0.4,entryEdges:[3],exitEdges:[1])]
        try draft.addRoutePoint(a.world(.init(1,3)))
        var top=a.world(.init(3,3)); top.y=0.4
        try draft.addRoutePoint(top)
        XCTAssertEqual(draft.route[1].y,0.4)
        try draft.addRoutePoint(a.world(.init(5,3)),asDestination:true)
        XCTAssertTrue(draft.routeErrors.isEmpty)
        let saved=try draft.stageRoute()
        let loaded=try JSONDecoder().decode(StageRoute.self,from:JSONEncoder().encode(saved))
        XCTAssertEqual(loaded.pointHeights,[0,0.4,0])
        var wrong=draft; wrong.route=[]; wrong.routeFinished=false
        try wrong.addRoutePoint(a.world(.init(3,1)))
        XCTAssertThrowsError(try wrong.addRoutePoint(top))
        var tooHigh=top; tooHigh.y=ObjectHeight.ceiling+0.1
        XCTAssertFalse(draft.acceptsRouteSurface(tooHigh,in:a))
        var outside=a.world(.init(1,1)); outside.y=0.4
        XCTAssertFalse(draft.acceptsRouteSurface(outside,in:a))
        draft.objects[0].kind = .stairs
        var tread=top; tread.y=0.2
        XCTAssertTrue(draft.acceptsRouteSurface(tread,in:a))
        draft.objects[0].height=nil
        XCTAssertTrue(draft.acceptsRouteSurface(top,in:a))
    }
}
