import Foundation

public enum PlaceKind: String, Codable, CaseIterable, Sendable {
    case rehearsal, theater
    public var title: String { self == .rehearsal ? "연습장" : "공연장" }
}

public struct PlaceSubfolder: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) { self.id=id; self.name=name }
}

public struct PlaceEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var address: String
    public var kind: PlaceKind
    public var photoID: UUID
    public var folders: [PlaceSubfolder]
    public var favorite: Bool
    public var createdAt: Date
    public var lastOpenedAt: Date?
    public init(id: UUID = UUID(), name: String, address: String, kind: PlaceKind,
                photoID: UUID = UUID(), folders: [PlaceSubfolder] = [], favorite: Bool = false,
                createdAt: Date = Date(), lastOpenedAt: Date? = nil) {
        self.id=id; self.name=name; self.address=address; self.kind=kind; self.photoID=photoID
        self.folders=folders; self.favorite=favorite; self.createdAt=createdAt; self.lastOpenedAt=lastOpenedAt
    }
    public func validate() throws {
        try Self.check(name, limit:80, message:"장소 이름은 1~80자로 입력해주세요.")
        try Self.check(address, limit:200, message:"위치는 1~200자로 입력해주세요.")
        guard Set(folders.map(\.id)).count == folders.count else { throw LabError.invalid("폴더 식별자가 중복됩니다.") }
        for folder in folders { try Self.check(folder.name, limit:80, message:"폴더 이름은 1~80자로 입력해주세요.") }
        guard Set(folders.map { PlaceSearch.normalized($0.name) }).count == folders.count else {
            throw LabError.invalid("같은 장소 안에서는 폴더 이름을 다르게 입력해주세요.")
        }
    }
    private static func check(_ value: String, limit: Int, message: String) throws {
        guard !value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, value.count <= limit else {throw LabError.invalid(message)}
    }
}

public struct PlaceDestination: Codable, Equatable, Hashable, Sendable {
    public var placeID: UUID
    public var folderID: UUID?
    public init(placeID: UUID, folderID: UUID? = nil) { self.placeID=placeID; self.folderID=folderID }
}

/// Sidecar classification only. ScanManifest, ARWorldMap, meshes and guidance records are never rewritten.
public struct PlaceFolderIndex: Codable, Equatable, Sendable {
    public var version = 1
    public var places: [PlaceEntry] = []
    public var assignments: [UUID: PlaceDestination] = [:]
    public var favoriteScans: Set<UUID> = []
    public init() {}
    public func contains(_ destination: PlaceDestination) -> Bool {
        guard let place=places.first(where:{$0.id == destination.placeID}) else {return false}
        return destination.folderID == nil || place.folders.contains {$0.id == destination.folderID}
    }
    public func destination(for scanID: UUID) -> PlaceDestination? {
        guard let value=assignments[scanID], contains(value) else {return nil}
        return value
    }
    public func path(for scanID: UUID) -> [String] {
        guard let destination=destination(for:scanID), let place=places.first(where:{$0.id==destination.placeID}) else {return ["장소 미지정"]}
        var result=[place.name]
        if let folder=place.folders.first(where:{$0.id==destination.folderID}) {result.append(folder.name)}
        return result
    }
    public func validate() throws {
        guard version == 1 else {throw LabError.invalid("지원하지 않는 장소 보관함 버전입니다.")}
        guard Set(places.map(\.id)).count == places.count else {throw LabError.invalid("장소 식별자가 중복됩니다.")}
        for place in places {try place.validate()}
        guard assignments.values.allSatisfy(contains) else {throw LabError.invalid("공연의 저장 폴더를 찾을 수 없습니다.")}
    }
}

public enum PlaceSort: String, CaseIterable, Sendable {
    case recent, name, created
    public var title: String {switch self {case .recent: return "최근 사용순"; case .name: return "이름순"; case .created: return "최근 등록순"}}
    public func sorted(_ places: [PlaceEntry]) -> [PlaceEntry] {
        places.sorted { a,b in
            switch self {
            case .recent:
                let x=a.lastOpenedAt ?? a.createdAt, y=b.lastOpenedAt ?? b.createdAt
                if x != y {return x > y}
            case .created: if a.createdAt != b.createdAt {return a.createdAt > b.createdAt}
            case .name: if a.name != b.name {return a.name.localizedStandardCompare(b.name) == .orderedAscending}
            }
            return a.id.uuidString < b.id.uuidString
        }
    }
}

public struct PlaceSearchResults: Sendable {
    public let places: [PlaceEntry]
    public let performances: [ScanManifest]
    public let matchesPerformanceName: Bool
}
public enum PlaceSearch {
    public static func normalized(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:Locale(identifier:"ko_KR"))
            .split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
    }
    public static func search(_ query: String, index: PlaceFolderIndex, scans: [ScanManifest]) -> PlaceSearchResults {
        let terms=normalized(query).split(separator:" ").map(String.init)
        guard !terms.isEmpty else {return .init(places:[],performances:[],matchesPerformanceName:false)}
        func matches(_ text: String) -> Bool {let haystack=normalized(text); return terms.allSatisfy {haystack.contains($0)}}
        let places=index.places.filter {matches(([$0.name,$0.address,$0.kind.title]+$0.folders.map(\.name)).joined(separator:" "))}
        let performances=scans.filter {scan in
            var fields=[scan.name]+index.path(for:scan.id)
            if let d=index.destination(for:scan.id), let p=index.places.first(where:{$0.id==d.placeID}) {fields += [p.address,p.kind.title]}
            return matches(fields.joined(separator:" "))
        }.sorted {if $0.date != $1.date {return $0.date > $1.date}; return $0.id.uuidString < $1.id.uuidString}
        return .init(places:PlaceSort.name.sorted(places),performances:performances,matchesPerformanceName:performances.contains {matches($0.name)})
    }
}
