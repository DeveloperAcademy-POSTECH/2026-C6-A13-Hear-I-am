import XCTest
@testable import HearIAmCore

final class PerformanceVoiceMenuTests:XCTestCase {
    func testOnePerformanceContainsSeveralVenueStagesWithoutDuplicatingItsNumber() {
        let first=UUID(),second=UUID(),folder=PerformanceFolder(name:"Lion King")
        var catalog=PerformanceCatalog();catalog.performances=[folder]
        catalog.assignments[first] = .init(performanceID:folder.id,venueID:nil)
        catalog.assignments[second] = .init(performanceID:folder.id,venueID:nil)
        let choices=PerformanceVoiceMenu.choices(catalog:catalog,stageIDs:[second,first])
        XCTAssertEqual(choices.count,1);XCTAssertEqual(choices.first?.stageIDs,[second,first])
    }
    /// There are no unfiled stages any more (#181): one left behind is not offered, nor is an empty folder.
    func testUnassignedScanAndEmptyFolderAreNotOffered() {
        let scan=UUID();var catalog=PerformanceCatalog();catalog.performances=[.init(name:"빈 공연")]
        XCTAssertEqual(PerformanceVoiceMenu.choices(catalog:catalog,stageIDs:[scan]),[])
    }
    func testVenueSearchOnlyOffersMatchingPerformances() {
        let a=UUID(),b=UUID();let first=PerformanceFolder(name:"A"),second=PerformanceFolder(name:"B")
        var catalog=PerformanceCatalog();catalog.performances=[first,second]
        catalog.assignments[a] = .init(performanceID:first.id);catalog.assignments[b] = .init(performanceID:second.id)
        XCTAssertEqual(PerformanceVoiceMenu.choices(catalog:catalog,stageIDs:[b]).map(\.id),[second.id])
    }
}
