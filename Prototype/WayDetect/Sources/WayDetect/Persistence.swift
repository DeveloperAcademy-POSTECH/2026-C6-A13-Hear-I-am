import Combine
import Foundation
import WayDetectCore

@MainActor
final class AppStore: ObservableObject {
    @Published var routes: [Route] = []
    @Published var sessions: [SessionRecord] = []
    @Published var settings = TrackingSettings()
    @Published var errorMessage: String?
    @Published var interruptedRecord: SessionRecord?
    private let root: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }()
    private let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacy = support.appendingPathComponent("WayDetect")
        root = support.appendingPathComponent(testing ? "WayDetect-POC-UITests" : "WayDetect/POC-v2")
        if testing && !ProcessInfo.processInfo.arguments.contains("--preserve-ui-test-data") { try? FileManager.default.removeItem(at: root) }
        do {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("Sessions"), withIntermediateDirectories: true)
            routes = try read([Route].self, "routes.json") ?? (testing ? [.example] : migratedRoutes(from: legacy))
            routes = routes.filter { $0.validationMessage == nil }
            if routes.isEmpty { routes = [.example] }
            if testing && ProcessInfo.processInfo.arguments.contains("--short-test-route") {
                routes = [Route(name: "두 스팟 시험", spots: [.init(name: "첫 스팟", clock: 12, steps: 2), .init(name: "도착점", clock: 3, steps: 2)])]
            }
            settings = try read(TrackingSettings.self, "settings.json") ?? (testing ? .init() : migratedSettings(from: legacy))
            let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Sessions"), includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "json" {
                do { sessions.append(try decoder.decode(SessionRecord.self, from: Data(contentsOf: file))) }
                catch { errorMessage = "일부 기록을 읽지 못했습니다. 원본 파일은 보존했습니다." }
            }
            sessions.sort { $0.startedAt > $1.startedAt }
            interruptedRecord = try read(SessionRecord.self, "active-session.json")
            if let active = interruptedRecord, sessions.contains(where: { $0.id == active.id }) {
                interruptedRecord = nil; try? FileManager.default.removeItem(at: root.appendingPathComponent("active-session.json"))
            }
        } catch { errorMessage = "데이터를 읽지 못했습니다. 원본은 보존했습니다. \(error.localizedDescription)" }
    }
    /// Preserve old files verbatim. Convert only the v1 route editor's walk/turn sequence.
    private func migratedRoutes(from folder: URL) -> [Route] {
        struct OldStep: Decodable { var kind: String; var steps: Int; var turnDegrees: Int }
        struct OldRoute: Decodable { var id: UUID; var name: String; var steps: [OldStep] }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("routes.json")),
              let old = try? decoder.decode([OldRoute].self, from: data) else { return [.example] }
        return old.compactMap { old in
            var spots: [RouteSpot] = [], turn = 0
            for step in old.steps {
                if step.kind == "turn" { turn += step.turnDegrees }
                if step.kind == "walk" {
                    spots.append(RouteSpot(name: "스팟 \(spots.count + 1)", clock: Angles.clock(Double(turn)), steps: step.steps)); turn = 0
                }
            }
            var route = Route(name: old.name, spots: spots); route.id = old.id
            return route.validationMessage == nil ? route : nil
        }
    }
    private func migratedSettings(from folder: URL) -> TrackingSettings {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("settings.json")),
              let value = try? decoder.decode(TrackingSettings.self, from: data) else { return .init() }
        return value
    }
    func saveRoute(_ route: Route) {
        guard route.validationMessage == nil else { errorMessage = route.validationMessage; return }
        var updated = routes
        if let i = updated.firstIndex(where: { $0.id == route.id }) { updated[i] = route } else { updated.append(route) }
        if write(updated, "routes.json") { routes = updated }
    }
    func deleteRoutes(at offsets: IndexSet) {
        var updated = routes
        for index in offsets.sorted(by: >) { updated.remove(at: index) }
        if write(updated, "routes.json") { routes = updated }
    }
    func saveSettings() { _ = write(settings, "settings.json") }
    func checkpoint(_ record: SessionRecord) { _ = write(record, "active-session.json") }
    @discardableResult func saveSession(_ record: SessionRecord) -> Bool {
        guard write(record, "Sessions/\(record.id.uuidString).json") else { return false }
        sessions.removeAll { $0.id == record.id }; sessions.insert(record, at: 0)
        do {
            let file = root.appendingPathComponent("active-session.json")
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        } catch { errorMessage = "결과는 저장했지만 임시 기록 정리에 실패했습니다." }
        return true
    }
    func archiveInterrupted() {
        guard var record = interruptedRecord else { return }
        if record.endedAt == nil {
            record.outcome = "앱 종료로 중단"; record.endedAt = record.startedAt.addingTimeInterval(record.duration)
        }
        if saveSession(record) { interruptedRecord = nil }
    }
    @discardableResult func discardPendingSession(id: UUID) -> Bool {
        do {
            if let active = try read(SessionRecord.self, "active-session.json") {
                guard active.id == id else { errorMessage = "다른 임시 기록이 있어 삭제하지 못했습니다."; return false }
                try FileManager.default.removeItem(at: root.appendingPathComponent("active-session.json"))
            }
            if interruptedRecord?.id == id { interruptedRecord = nil }; return true
        } catch { errorMessage = "임시 기록을 지우지 못했습니다. \(error.localizedDescription)"; return false }
    }
    func deleteSession(_ record: SessionRecord) {
        do {
            try FileManager.default.removeItem(at: root.appendingPathComponent("Sessions/\(record.id.uuidString).json"))
            sessions.removeAll { $0.id == record.id }
        } catch { errorMessage = "기록을 삭제하지 못했습니다." }
    }
    func export(_ record: SessionRecord, csv: Bool) -> URL? {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("WayDetect-\(record.id.uuidString).\(csv ? "csv" : "json")")
            if csv {
                let header = "time_s,spot,revision,phase,target_clock_from_current_front,leg_steps,leg_goal,imu_estimated_total,ios_total,vertical_acceleration_g,sensor_age_s,sensor_valid,is_demo,rotation_rate_deg_s,acceleration_g,horizontal_projection,gravity_residual_g"
                let rows = record.samples.map { s in
                    [String(s.time), String(s.spot + 1), String(s.revision), s.phase.rawValue, String(Angles.clock(s.error)),
                     String(s.steps), String(s.stepGoal), String(s.estimatedTotal), String(s.systemTotal),
                     String(s.verticalAcceleration), String(s.sensorAge), String(s.sensorValid), String(record.isDemo),
                     String(s.rotationRate), String(s.accelerationMagnitude), String(s.horizontalProjection), String(s.gravityResidual)].joined(separator: ",")
                }
                try ("\u{FEFF}" + ([header] + rows).joined(separator: "\n")).write(to: url, atomically: true, encoding: .utf8)
            } else { try encoder.encode(record).write(to: url, options: .atomic) }
            return url
        } catch { errorMessage = "내보내기에 실패했습니다. \(error.localizedDescription)"; return nil }
    }
    private func read<T: Decodable>(_ type: T.Type, _ name: String) throws -> T? {
        let file = root.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try decoder.decode(type, from: Data(contentsOf: file))
    }
    @discardableResult private func write<T: Encodable>(_ value: T, _ name: String) -> Bool {
        do { try encoder.encode(value).write(to: root.appendingPathComponent(name), options: .atomic); return true }
        catch { errorMessage = "저장 실패: \(error.localizedDescription)"; return false }
    }
}
