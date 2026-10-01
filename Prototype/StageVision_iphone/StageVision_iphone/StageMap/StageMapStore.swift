import Foundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class StageMapStore: ObservableObject {
    @Published private(set) var map: StageMap?
    @Published private(set) var canUndo = false
    @Published private(set) var isDirty = false
    @Published var message: String?
    private var history: [StageMap] = []
    static var directory: URL { URL.documentsDirectory.appendingPathComponent("StageMaps", isDirectory: true) }
    private let storageDirectory: URL
    private var latestURL: URL { storageDirectory.appendingPathComponent("latest.json") }

    init(directory: URL? = nil) {
        storageDirectory = directory ?? Self.directory
        guard FileManager.default.fileExists(atPath: latestURL.path) else { return }
        do {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            var saved = try decoder.decode(StageMap.self, from: Data(contentsOf: latestURL))
            try saved.validated(); saved.rebuildRiskZones(); map = saved
        } catch { message = "저장 지도를 열지 못했습니다: \(error.localizedDescription)" }
    }
    func replace(_ value: StageMap) {
        if let map { history.append(map) }
        map = value; changed()
    }
    func edit(_ action: (inout StageMap) -> Void) {
        guard var current = map else { return }
        let old = current
        action(&current)
        guard current != old else { return }
        history.append(old)
        if current.floorPolygon != old.floorPolygon || current.boundarySegments != old.boundarySegments {
            current.rebuildRiskZones()
        }
        map = current; changed()
    }
    private func changed() {
        if history.count > 50 { history.removeFirst(history.count - 50) }
        canUndo = !history.isEmpty; isDirty = true
    }
    func undo() {
        guard let previous = history.popLast() else { return }
        map = previous; changed()
    }
    func movePoint(_ i: Int, to point: MapPoint) {
        edit { map in
            guard map.floorPolygon.indices.contains(i) else { return }
            map.floorPolygon[i] = point; map.reindex()
        }
    }
    func insertPoint(after edge: Int) {
        edit { map in
            guard map.floorPolygon.count < StageGeometry.maximumPoints, map.floorPolygon.indices.contains(edge) else { return }
            let next = (edge + 1) % map.floorPolygon.count
            let midpoint = (map.floorPolygon[edge] + map.floorPolygon[next]) * 0.5
            map.floorPolygon.insert(midpoint, at: edge + 1)
            map.boundarySegments.insert(map.boundarySegments[edge], at: edge + 1)
            map.reindex()
        }
    }
    func deletePoint(_ i: Int) {
        edit { map in
            guard map.floorPolygon.count > 3, map.floorPolygon.indices.contains(i) else { return }
            let previous = (i + map.floorPolygon.count - 1) % map.floorPolygon.count
            // Merge conservatively; never drop an enabled danger band when deleting a corner.
            map.boundarySegments[previous].riskEnabled = map.boundarySegments[previous].riskEnabled || map.boundarySegments[i].riskEnabled
            map.boundarySegments[previous].riskDistance = max(map.boundarySegments[previous].riskDistance, map.boundarySegments[i].riskDistance)
            if map.boundarySegments[previous].side != map.boundarySegments[i].side { map.boundarySegments[previous].side = .other }
            map.floorPolygon.remove(at: i); map.boundarySegments.remove(at: i); map.reindex()
        }
    }
    func document() throws -> StageMapDocument {
        guard var map else { throw StageMapError.invalid("먼저 무대를 스캔하세요.") }
        try map.validated()
        map.savedAt = Date(); map.rebuildRiskZones()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return StageMapDocument(data: try encoder.encode(map))
    }
    func save() {
        do {
            let doc = try document()
            try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            guard let map else { return }
            try doc.data.write(to: storageDirectory.appendingPathComponent("\(map.stageId).json"), options: .atomic)
            try doc.data.write(to: latestURL, options: .atomic)
            isDirty = false
            message = "StageMap JSON을 앱의 Documents/StageMaps에 저장했습니다. 다음 실행 때 마지막 지도를 불러옵니다."
        } catch { message = "저장 실패: \(error.localizedDescription)" }
    }
}
struct StageMapDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
