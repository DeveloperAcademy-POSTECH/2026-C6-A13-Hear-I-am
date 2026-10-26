import Foundation

public actor PlaceFolderStore {
    public let root: URL
    public static let maximumPhotoBytes = 4 * 1_024 * 1_024
    public init(root: URL) {self.root=root}
    private var indexURL: URL {root.appendingPathComponent("places.json")}
    private func photoURL(_ id: UUID) -> URL {root.appendingPathComponent("photos").appendingPathComponent(id.uuidString+".jpg")}
    public func load() throws -> PlaceFolderIndex {
        guard FileManager.default.fileExists(atPath:indexURL.path) else {return PlaceFolderIndex()}
        let index=try JSONDecoder().decode(PlaceFolderIndex.self,from:Data(contentsOf:indexURL))
        try index.validate()
        return index
    }
    private func commit(_ index: PlaceFolderIndex) throws -> PlaceFolderIndex {
        try index.validate()
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        try encoder.encode(index).write(to:indexURL,options:.atomic)
        return index
    }
    public func photo(_ id: UUID) throws -> Data {
        let url=photoURL(id)
        let info=try url.resourceValues(forKeys:[.fileSizeKey])
        guard let size=info.fileSize, size>0, size<=Self.maximumPhotoBytes else {throw LabError.invalid("장소 사진 크기가 올바르지 않습니다.")}
        return try Data(contentsOf:url)
    }
    /// Publish photo first, then the index. A failed index write preserves the prior photo and metadata.
    public func upsert(_ value: PlaceEntry, photo: Data? = nil) throws -> PlaceFolderIndex {
        var index=try load(), place=value
        place.name=place.name.trimmingCharacters(in:.whitespacesAndNewlines)
        place.address=place.address.trimmingCharacters(in:.whitespacesAndNewlines)
        for i in place.folders.indices {place.folders[i].name=place.folders[i].name.trimmingCharacters(in:.whitespacesAndNewlines)}
        let old=index.places.first {$0.id==place.id}
        if let old {place.createdAt=old.createdAt;place.lastOpenedAt=old.lastOpenedAt;place.favorite=old.favorite}
        try place.validate()
        var writtenPhoto: UUID?
        if let photo {
            guard !photo.isEmpty, photo.count<=Self.maximumPhotoBytes else {throw LabError.invalid("장소 사진은 4MB 이하로 저장해주세요.")}
            place.photoID=UUID()
            try FileManager.default.createDirectory(at:photoURL(place.photoID).deletingLastPathComponent(),withIntermediateDirectories:true)
            try photo.write(to:photoURL(place.photoID),options:.atomic)
            writtenPhoto=place.photoID
        } else {
            guard let old else {throw LabError.invalid("장소 사진을 선택해주세요.")}
            place.photoID=old.photoID
            _ = try self.photo(old.photoID)
        }
        index.places.removeAll {$0.id==place.id};index.places.append(place)
        // Removed subfolders release their scans to the unassigned collection; no scan files are touched.
        index.assignments=index.assignments.filter {index.contains($0.value)}
        do {
            let result=try commit(index)
            if let old, old.photoID != place.photoID {try? FileManager.default.removeItem(at:photoURL(old.photoID))}
            return result
        } catch {
            if let writtenPhoto {try? FileManager.default.removeItem(at:photoURL(writtenPhoto))}
            throw error
        }
    }
    public func deletePlace(_ id: UUID) throws -> PlaceFolderIndex {
        var index=try load()
        let old=index.places.first {$0.id==id}
        index.places.removeAll {$0.id==id}
        index.assignments=index.assignments.filter {$0.value.placeID != id}
        let result=try commit(index)
        if let old {try? FileManager.default.removeItem(at:photoURL(old.photoID))}
        return result
    }
    public func assign(_ scanIDs: Set<UUID>, to destination: PlaceDestination?) throws -> PlaceFolderIndex {
        var index=try load()
        if let destination, !index.contains(destination) {throw LabError.invalid("저장할 장소 또는 폴더가 없어졌어요. 다시 선택해주세요.")}
        for id in scanIDs {index.assignments[id]=destination}
        return try commit(index)
    }
    public func togglePlaceFavorite(_ id: UUID) throws -> PlaceFolderIndex {
        var index=try load()
        guard let i=index.places.firstIndex(where:{$0.id==id}) else {throw LabError.invalid("장소를 찾을 수 없어요.")}
        index.places[i].favorite.toggle()
        return try commit(index)
    }
    public func togglePerformanceFavorite(_ id: UUID) throws -> PlaceFolderIndex {
        var index=try load()
        if index.favoriteScans.contains(id) {index.favoriteScans.remove(id)} else {index.favoriteScans.insert(id)}
        return try commit(index)
    }
    public func visit(_ id: UUID, at date: Date = Date()) throws -> PlaceFolderIndex {
        var index=try load()
        guard let i=index.places.firstIndex(where:{$0.id==id}) else {return index}
        index.places[i].lastOpenedAt=date
        return try commit(index)
    }
}

/// Compare only one uninterrupted presentation of the existing scanner, never names or old assignments.
public struct PlaceScanReceipt: Sendable {
    public let existingIDs: Set<UUID>
    public let startedAt: Date
    public init(scans: [ScanManifest], startedAt: Date = Date()) {
        existingIDs=Set(scans.map(\.id));self.startedAt=startedAt
    }
    public func newScan(in scans: [ScanManifest]) throws -> UUID? {
        let candidates=scans.filter {!existingIDs.contains($0.id) && $0.date>=startedAt}
        guard candidates.count<=1 else {throw LabError.invalid("새 공연이 여러 개 발견됐어요. 장소 미지정에서 옮길 공연을 선택해주세요.")}
        return candidates.first?.id
    }
}
