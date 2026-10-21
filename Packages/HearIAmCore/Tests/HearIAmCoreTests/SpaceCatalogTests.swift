import XCTest
@testable import HearIAmCore

final class SpaceCatalogTests: XCTestCase {
    func testOfficialCatalogHasSixVenuesAndSourcesForEveryPhoto() throws {
        let venues=try OfficialSpaces.load()
        XCTAssertEqual(venues.count,6)
        XCTAssertEqual(venues.filter {$0.rooms.contains {$0.kind == .rehearsal}}.count,1)
        XCTAssertEqual(venues.filter {$0.rooms.contains {$0.kind == .theater}}.count,5)
        XCTAssertEqual(venues.first {$0.id=="hyoja"}?.rooms.first?.scale,.medium)
        XCTAssertEqual(venues.first {$0.id=="suseong"}?.rooms.first?.scale,.large)
        XCTAssertTrue(venues.allSatisfy {$0.photos.allSatisfy {!$0.credit.isEmpty}})
    }
    func testCapacityEdgesAndUnknownAreNotSmall() {
        XCTAssertNil(SeatScale.classify(nil));XCTAssertNil(SeatScale.classify(0))
        XCTAssertEqual(SeatScale.classify(299),.small)
        XCTAssertEqual(SeatScale.classify(300),.medium)
        XCTAssertEqual(SeatScale.classify(999),.medium)
        XCTAssertEqual(SeatScale.classify(1000),.large)
    }
    func testSearchFilterIntersectionUsesSameRoom() throws {
        let venues=try OfficialSpaces.load()
        var filter=SpaceFilter();filter.query=" 대구  대연습실 ";filter.baseOnly=true
        XCTAssertTrue(filter.apply(to:venues,favorites:[],baseRooms:["daegu-practice-small"],performanceRooms:[]).isEmpty)
        XCTAssertEqual(filter.apply(to:venues,favorites:[],baseRooms:["daegu-practice-large"],performanceRooms:[]).map(\.id),["daegu-practice"])
        filter=SpaceFilter();filter.kind = .theater;filter.scale = .small
        XCTAssertEqual(filter.apply(to:venues,favorites:[],baseRooms:[],performanceRooms:[]).count,3)
        filter.favoritesOnly=true
        XCTAssertEqual(filter.apply(to:venues,favorites:["sanwoollim"],baseRooms:[],performanceRooms:[]).map(\.id),["sanwoollim"])
    }
    func testEmptySearchListsCatalogButNoInventedAvailableScans() throws {
        let venues=try OfficialSpaces.load();var filter=SpaceFilter()
        XCTAssertEqual(filter.apply(to:venues,favorites:[],baseRooms:[],performanceRooms:[]).count,6)
        filter.baseOnly=true
        XCTAssertTrue(filter.apply(to:venues,favorites:[],baseRooms:[],performanceRooms:[]).isEmpty)
    }
}
