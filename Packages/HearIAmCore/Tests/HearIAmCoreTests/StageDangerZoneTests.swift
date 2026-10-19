import XCTest
@testable import HearIAmCore

final class StageDangerZoneTests: XCTestCase {
    func testEachEdgeUsesInwardDistanceForBothOptions() {
        for distance in StageDangerZone.Distance.allCases {
            let d=distance.rawValue
            let expected: [StageDangerZone.Edge:[FloorPoint]] = [
                .front:[.init(0,0),.init(6,0),.init(6,d),.init(0,d)],
                .back:[.init(0,4-d),.init(6,4-d),.init(6,4),.init(0,4)],
                .left:[.init(0,0),.init(d,0),.init(d,4),.init(0,4)],
                .right:[.init(6-d,0),.init(6,0),.init(6,4),.init(6-d,4)]]
            for edge in StageDangerZone.Edge.allCases {
                XCTAssertEqual(StageDangerZone(edge:edge,distance:distance).vertices(width:6,depth:4),expected[edge])
            }
        }
    }
    func testRotatedTranslatedStageKeepsAudienceRelativeEdges() throws {
        let area=try StageArea(corners:[.init(2,1,3),.init(2,1,9),.init(6,1,9),.init(6,1,3)])
        let back=StageDangerZone(edge:.back,distance:.oneMetre)
        let world=back.vertices(width:area.width,depth:area.depth).map(area.world)
        XCTAssertEqual(world,[.init(5,1,3),.init(5,1,9),.init(6,1,9),.init(6,1,3)])
        for p in world { XCTAssertTrue(area.contains(area.floor(p))) }
    }
    func testSmallStageClipsStripsAndInvalidDimensionsDoNotDraw() {
        for edge in StageDangerZone.Edge.allCases {
            let zone=StageDangerZone(edge:edge,distance:.oneMetre)
            let vertices=zone.vertices(width:0.6,depth:0.8)
            XCTAssertEqual(vertices,[.init(0,0),.init(0.6,0),.init(0.6,0.8),.init(0,0.8)])
            for invalid in [0.0,-1,.nan,.infinity] {
                XCTAssertTrue(zone.vertices(width:invalid,depth:4).isEmpty)
                XCTAssertTrue(zone.vertices(width:6,depth:invalid).isEmpty)
            }
        }
    }
    func testLegacyRoutesAndInvalidSavedSettings() throws {
        for outside in [false,true] {
            let route=try StageRoute(area:PerformancePlan.area,points:[.init(1,2),.init(2,2),.init(3,2)],obstacles:[],allowsOutsideEndpoints:outside)
            var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(route)) as? [String:Any])
            json.removeValue(forKey:"dangerZones")
            let legacy=try JSONDecoder().decode(StageRoute.self,from:JSONSerialization.data(withJSONObject:json))
            XCTAssertEqual(legacy,route)
            for invalid: [[String:Any]] in [
                [["edge":"front","distance":0.75]],
                [["edge":"unknown","distance":0.5]],
                [["edge":"front","distance":0.5],["edge":"front","distance":1.0]]
            ] {
                json["dangerZones"]=invalid
                XCTAssertThrowsError(try JSONDecoder().decode(StageRoute.self,from:JSONSerialization.data(withJSONObject:json)))
            }
        }
    }
    func testDraftBoundaryEditsAndOutsideRouteKeepSettingsWithoutNewBlocking() throws {
        var draft=PreparationDraft()
        draft.corners=PerformancePlan.area.corners.map { Optional($0) }
        draft.dangerZones=[.init(edge:.left,distance:.oneMetre),.init(edge:.right,distance:.halfMetre)]
        try draft.addRoutePoint(.init(-1,0,-2));try draft.addRoutePoint(.init(2,0,-2))
        try draft.addRoutePoint(.init(13,0,-2),asDestination:true)
        let route=try draft.stageRoute()
        XCTAssertEqual(route.dangerZones,draft.dangerZones)
        XCTAssertTrue(draft.routeErrors.isEmpty)
        draft.corners=try StageArea(corners:[.init(0,0,0),.init(10,0,0),.init(10,0,-6),.init(0,0,-6)]).corners.map { Optional($0) }
        let edited=try draft.stageRoute()
        XCTAssertEqual(edited.dangerZones,route.dangerZones)
        let strip=try XCTUnwrap(edited.dangerZones.last).vertices(width:edited.area.width,depth:edited.area.depth)
        XCTAssertEqual(strip[0],.init(9.5,0));XCTAssertEqual(strip[2],.init(10,6))
        draft.dangerZones=[]
        XCTAssertTrue(try draft.stageRoute().dangerZones.isEmpty)
    }
    func testContainmentIncludesBorderButExcludesOutsideAndInvalidPoints() {
        for edge in StageDangerZone.Edge.allCases {
            for distance in StageDangerZone.Distance.allCases {
                let zone=StageDangerZone(edge:edge,distance:distance)
                let vertices=zone.vertices(width:6,depth:4)
                for vertex in vertices { XCTAssertTrue(zone.contains(vertex,width:6,depth:4)) }
                XCTAssertFalse(zone.contains(.init(3,2),width:6,depth:4))
                for point in [FloorPoint(-0.01,0),.init(6.01,4),.init(0,-0.01),.init(0,4.01),.init(.nan,0)] {
                    XCTAssertFalse(zone.contains(point,width:6,depth:4))
                }
            }
        }
    }
    /// Since 10/19 a new point keeps 0.15 m from a danger zone, start and destination included; until then
    /// zones only warned. Points already in a zone (an applied plan, a zone added later) are still labelled.
    func testNewPointsKeepClearOfZonesAndOldPointsAreStillLabelled() throws {
        var draft=PreparationDraft()
        draft.corners=PerformancePlan.area.corners.map { Optional($0) }
        draft.dangerZones=[.init(edge:.front,distance:.halfMetre),.init(edge:.left,distance:.oneMetre)]
        XCTAssertThrowsError(try draft.addRoutePoint(.init(3,0,-0.25)))
        XCTAssertEqual(draft.edgeIssue(adding:.init(3,0,-0.6)),"위험 구역(앞 (객석 쪽))에서 15cm 이상 떨어진 곳을 찍어주세요")
        try draft.addRoutePoint(.init(3,0,-0.7))
        XCTAssertNotNil(draft.edgeIssue(adding:.init(1.1,0,-2)))
        try draft.addRoutePoint(.init(2,0,-2))
        XCTAssertThrowsError(try draft.addRoutePoint(.init(4,0,-0.3),asDestination:true))
        try draft.addRoutePoint(.init(4,0,0.5),asDestination:true)
        XCTAssertTrue(draft.dangerZoneRoutePointLabels.isEmpty)
        XCTAssertTrue(draft.routeErrors.isEmpty)
        draft.dangerZones=[.init(edge:.front,distance:.oneMetre)]
        XCTAssertEqual(draft.dangerZoneRoutePointLabels,["시작점"])
        draft.dangerZones=[]
        XCTAssertTrue(draft.dangerZoneRoutePointLabels.isEmpty)
    }
    func testArchiveLoadAndRenamePreservePerEdgeSettings() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=ScanStore(root:root), area=PerformancePlan.area
        let zones=StageDangerZone.Edge.allCases.enumerated().map {
            StageDangerZone(edge:$0.element,distance:$0.offset.isMultiple(of:2) ? .halfMetre : .oneMetre)
        }
        let route=try StageRoute(area:area,points:[.init(-1,2),.init(2,2),.init(13,2)],obstacles:[],allowsOutsideEndpoints:true,dangerZones:zones)
        let frame=try StageFrame(origin:area.world(.init(0,0)),front:area.world(.init(0,-1)))
        let mesh=MeshSnapshot(id:UUID(),transform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],vertices:[.init(0,0,0),.init(1,0,0),.init(0,0,-1)],indices:[0,1,2])
        let id=UUID()
        _=try await store.save(id:id,name:"위험 구역 무대",frame:frame,checkpoint:area.world(.init(6,4)),worldMap:Data([1,2,3]),meshes:[mesh],device:"test",appVersion:"1",route:route)
        _=try await store.rename(id,to:"이름 수정")
        let loaded=try await ScanStore(root:root).load(id)
        XCTAssertEqual(loaded.manifest.route,route)
        XCTAssertEqual(loaded.manifest.route?.dangerZones,zones)
    }
}
