import XCTest
@testable import HearIAmCore

final class PerformancePlanV3Tests: XCTestCase {
    private func plan() throws -> PerformancePlan {
        var value=PerformancePlan();value.name="Lion King"
        try value.append(.init(1,1));try value.append(.init(4,3));try value.append(.init(8,3));try value.finishRoute()
        return value
    }
    func testLegacyPlanDecodesAndPointInstructionsRoundTripWithoutChangingVenueRoute() throws {
        var source=try plan()
        let original=try StageRoute(area:PerformancePlan.area,points:source.points,obstacles:source.objects)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(source)) as? [String:Any])
        json.removeValue(forKey:"pointSettings");json.removeValue(forKey:"objectFacings")
        source=try JSONDecoder().decode(PerformancePlan.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertEqual(source.pointSettings.count,3)
        try source.setPointSettings(.init(name:"중앙 대사",holdSeconds:10,facing:.northEast),at:1)
        let restored=try JSONDecoder().decode(PerformancePlan.self,from:JSONEncoder().encode(source))
        XCTAssertEqual(restored.settings(at:1).holdSeconds,10)
        XCTAssertEqual(restored.settings(at:1).facing,.northEast)
        XCTAssertEqual(original.holdSeconds(at:1),0);XCTAssertNil(original.facing(at:1))
        XCTAssertThrowsError(try source.setPointSettings(.init(holdSeconds:1),at:0))
        XCTAssertThrowsError(try source.setPointSettings(.init(holdSeconds:1),at:2))
        XCTAssertThrowsError(try source.setPointSettings(.init(holdSeconds:3601),at:1))
        source.undoPoint();XCTAssertEqual(source.pointSettings.count,source.points.count)
        XCTAssertEqual(source.settings(at:1).holdSeconds,0)
    }
    func testObjectResizeRejectsOutsideStageAndDeletionRemovesChairDirection() throws {
        var value=try plan()
        try value.addObject(at:.init(10,6),platform:true)
        let id=try XCTUnwrap(value.objects.last?.id)
        value.objectFacings[id] = .northEast
        let before=value.objects
        XCTAssertThrowsError(try value.resizeObject(id,width:12,depth:8))
        XCTAssertEqual(value.objects,before)
        try value.resizeObject(id,width:2,depth:2);try value.validate()
        value.removeObject(id);XCTAssertNil(value.objectFacings[id]);try value.validate()
    }
}
