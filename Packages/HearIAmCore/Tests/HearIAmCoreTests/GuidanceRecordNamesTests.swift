import XCTest
@testable import HearIAmCore

/// A record keeps the performance and space its stage was filed under when the run finished (#179).
final class GuidanceRecordNamesTests: XCTestCase {
    private func record(performance: String?, venue: String?) throws -> GuidanceRecord {
        let route=try StageRoute(area:PerformancePlan.area,points:[.init(2,2),.init(4,2),.init(6,2)],obstacles:[])
        let start=Date(timeIntervalSince1970:1_700_000_000)
        return GuidanceRecord(version:1,id:UUID(),stageID:UUID(),stageName:"장면1",route:route,startedAt:start,completedAt:start+60,
                              finishedAt:start+61,activeSeconds:60,performanceName:performance,venueName:venue)
    }

    func testNamesSurviveSavingAndLoading() throws {
        let value=try record(performance:"뱀파이어",venue:"")
        let decoded=try JSONDecoder().decode(GuidanceRecord.self,from:JSONEncoder().encode(value))
        XCTAssertEqual(decoded.performanceName,"뱀파이어");XCTAssertEqual(decoded.venueName,"")
        XCTAssertEqual(decoded,value)
    }

    func testRecordsSavedBeforeHaveNoNames() throws {
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(try record(performance:"뱀파이어",venue:"홀"))) as? [String:Any])
        json.removeValue(forKey:"performanceName");json.removeValue(forKey:"venueName")
        let decoded=try JSONDecoder().decode(GuidanceRecord.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertNil(decoded.performanceName);XCTAssertNil(decoded.venueName)
        XCTAssertNoThrow(try decoded.validate())
    }
}
