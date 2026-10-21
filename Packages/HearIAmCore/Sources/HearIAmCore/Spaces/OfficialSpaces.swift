import Foundation

public enum OfficialSpaces {
    public static func load() throws -> [SpaceVenue] {
        guard let url=Bundle.module.url(forResource:"venues",withExtension:"json") else {
            throw LabError.invalid("공간 목록을 찾지 못했습니다.")
        }
        let venues=try JSONDecoder().decode([SpaceVenue].self,from:Data(contentsOf:url))
        let roomIDs=venues.flatMap { $0.rooms.map(\.id) }
        guard Set(venues.map(\.id)).count==venues.count, Set(roomIDs).count==roomIDs.count,
              venues.allSatisfy({ !$0.rooms.isEmpty && $0.source.scheme=="https" && $0.rooms.allSatisfy { room in
                  !room.photos.isEmpty && room.photos.allSatisfy {$0.url.scheme=="https" && $0.source.scheme=="https"}
              }}) else { throw LabError.invalid("공간 목록의 식별자 또는 출처를 확인해주세요.") }
        return venues
    }
}
