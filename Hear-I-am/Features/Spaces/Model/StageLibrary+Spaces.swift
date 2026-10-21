import Foundation
import HearIAmCore

extension StageLibrary {
    func loadSpaces() {
        do {venues=try OfficialSpaces.load()}
        catch {self.error=error.localizedDescription}
        guard FileManager.default.fileExists(atPath:spacePreferencesURL.path) else {return}
        do {spacePreferences=try JSONDecoder().decode(SpaceLibraryPreferences.self,from:Data(contentsOf:spacePreferencesURL))}
        catch {spacePreferencesReadable=false;self.error="공간 즐겨찾기를 읽지 못했어요. 기존 파일은 유지됩니다: \(error.localizedDescription)"}
    }
    func updateSpaces(_ change: (inout SpaceLibraryPreferences) -> Void) {
        guard spacePreferencesReadable else {error="저장된 공간 설정을 먼저 복구해주세요.";return}
        var next=spacePreferences;change(&next)
        do {try JSONEncoder().encode(next).write(to:spacePreferencesURL,options:.atomic);spacePreferences=next}
        catch {self.error="공간 설정 저장 실패: \(error.localizedDescription)"}
    }
    func favoriteVenue(_ id: String) {
        updateSpaces {if !$0.favorites.insert(id).inserted {$0.favorites.remove(id)}}
    }
    func visitRoom(_ id: String) {updateSpaces {$0.visit(id)}}
    func performances(in room: String) -> [ScanManifest] {records.filter {$0.space?.roomID==room}}
    func bases(in room: String) -> [ScanManifest] {baseScans.filter {$0.space?.roomID==room}}
    var baseRoomIDs: Set<String> {Set(baseScans.compactMap {$0.space?.roomID})}
    var performanceRoomIDs: Set<String> {Set(records.compactMap {$0.space?.roomID})}
    var unassignedScans: [ScanManifest] {records.filter {$0.space == nil}}
    func assignScan(_ id: UUID, venue: SpaceVenue, room: VenueRoom) async {
        do {_ = try await scans.assign(id,venueID:venue.id,roomID:room.id);await refresh();visitRoom(room.id)}
        catch {self.error=error.localizedDescription}
    }
}

struct SpacePreparationRequest: Identifiable {
    let id=UUID()
    let context: ScanSpaceContext
    let base: ScanManifest?
    let title: String
}

extension VenueRoom {
    var subtitle: String {
        [floor,area.map {String(format:"%.2f㎡",$0)},seats.map {"\($0)석"}].compactMap {$0}.joined(separator:" · ")
    }
}
