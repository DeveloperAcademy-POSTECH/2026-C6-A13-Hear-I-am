import Foundation

public enum SpaceKind: String, Codable, CaseIterable, Sendable {
    case rehearsal, theater
    public var label: String { self == .rehearsal ? "연습장" : "공연장" }
}
public enum SeatScale: String, Codable, CaseIterable, Sendable {
    case small, medium, large
    public var label: String { switch self {case .small: return "소규모"; case .medium: return "중규모"; case .large: return "대규모"} }
    public var detail: String { switch self {case .small: return "300석 미만"; case .medium: return "300–999석"; case .large: return "1,000석 이상"} }
    public static func classify(_ seats: Int?) -> Self? {
        guard let seats, seats > 0 else { return nil }
        return seats < 300 ? .small : seats < 1000 ? .medium : .large
    }
}
public struct SpacePhoto: Codable, Hashable, Sendable, Identifiable {
    public var id: String { url.absoluteString }
    public let url: URL
    public let caption: String
    public let credit: String
    public let source: URL
    public init(url: URL, caption: String, credit: String, source: URL) {
        self.url=url;self.caption=caption;self.credit=credit;self.source=source
    }
}
public struct VenueRoom: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let kind: SpaceKind
    public let floor: String?
    public let area: Double?
    public let seats: Int?
    public let photos: [SpacePhoto]
    public let source: URL
    public var scale: SeatScale? { kind == .theater ? SeatScale.classify(seats) : nil }
    public init(id: String, name: String, kind: SpaceKind, floor: String? = nil, area: Double? = nil, seats: Int? = nil, photos: [SpacePhoto], source: URL) {
        self.id=id;self.name=name;self.kind=kind;self.floor=floor;self.area=area;self.seats=seats;self.photos=photos;self.source=source
    }
}
public struct SpaceVenue: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let region: String
    public let address: String
    public let rooms: [VenueRoom]
    public let source: URL
    /// The catalog review date, not a claim that its AR scan or onsite conditions were verified.
    public let checkedOn: String
    public let addedOrder: Int
    public var photos: [SpacePhoto] { rooms.first?.photos ?? [] }
    public init(id: String, name: String, region: String, address: String, rooms: [VenueRoom], source: URL, checkedOn: String, addedOrder: Int) {
        self.id=id;self.name=name;self.region=region;self.address=address;self.rooms=rooms;self.source=source;self.checkedOn=checkedOn;self.addedOrder=addedOrder
    }
}
public struct SpaceFilter: Equatable, Sendable {
    public var query=""
    public var kind: SpaceKind?
    public var region: String?
    public var scale: SeatScale?
    public var favoritesOnly=false
    public var baseOnly=false
    public var performancesOnly=false
    public var newestFirst=false
    public init() {}
    public func apply(to venues: [SpaceVenue], favorites: Set<String>, baseRooms: Set<String>, performanceRooms: Set<String>) -> [SpaceVenue] {
        let words=query.trimmingCharacters(in:.whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).map(String.init)
        return venues.filter { venue in
            if let region, venue.region != region { return false }
            if favoritesOnly && !favorites.contains(venue.id) { return false }
            // All room-specific predicates must match the SAME internal room.
            return venue.rooms.contains { room in
                let haystack=[venue.name,venue.address,venue.region,room.name,room.kind.label].joined(separator:" ")
                return words.allSatisfy { haystack.localizedStandardContains($0) }
                    && (kind == nil || room.kind == kind)
                    && (scale == nil || room.scale == scale)
                    && (!baseOnly || baseRooms.contains(room.id))
                    && (!performancesOnly || performanceRooms.contains(room.id))
            }
        }.sorted { a,b in
            if newestFirst && a.addedOrder != b.addedOrder { return a.addedOrder > b.addedOrder }
            return a.name.compare(b.name,locale:Locale(identifier:"ko_KR")) == .orderedAscending
        }
    }
}
