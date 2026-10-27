import SwiftUI
import HearIAmCore

@main struct QAApp: App {
    @UIApplicationDelegateAdaptor(HearAppDelegate.self) var appDelegate
    var body: some Scene {WindowGroup {QARoot().preferredColorScheme(.light)}}
}
struct QARoot: View {
    @State private var ready=false
    @State private var error:String?
    var body: some View {
        Group {
            if ready {HearRootView()}
            else if let error {Text(error)}
            else {ProgressView().task {do {try await QAFixtures.seed();ready=true} catch {self.error=error.localizedDescription}}}
        }
    }
}
@MainActor enum QAFixtures {
    static let ids=(0...3).map {UUID(uuidString:String(format:"86000000-0000-0000-0000-%012d",$0+1))!}
    static let rehearsal=PlaceEntry(id:ids[0],name:"대구공연예술연습공간",address:"대구 남구 명덕로 42",kind:.rehearsal,folders:[.init(id:ids[3],name:"대연습실"),.init(name:"소연습실")],favorite:true)
    static let theater=PlaceEntry(id:ids[1],name:"효자아트홀",address:"경북 포항시 남구",kind:.theater)
    static func route() throws -> StageRoute {
        let area=try StageArea(corners:[.init(0,0,0),.init(6,0,0),.init(6,0,-4),.init(0,0,-4)])
        let chair=try StageObstacle(name:"의자",kind:.platform,vertices:[.init(4.7,2.7),.init(5.3,2.7),.init(5.3,3.3),.init(4.7,3.3)],height:0.5,facingEdge:0)
        return try StageRoute(area:area,points:[.init(0.5,0.5),.init(1.5,1.5),.init(3,1.5),.init(4,2),.init(5.5,3.5)],obstacles:[chair],pointHeights:[0,0,0,0,0])
    }
    static func manifest(name:String="Look at me", id:UUID=UUID()) throws -> ScanManifest {
        let r=try route()
        return ScanManifest(id:id,name:name,frame:try StageFrame(origin:r.area.world(.init(0,0)),front:r.area.world(.init(0,-1))),checkpoint:r.area.world(.init(1,3)),worldMapHash:"qa",meshHash:"qa",meshCount:1,vertexCount:4,device:"UI 예시",appVersion:"86",route:r,secondCheckpoint:r.area.world(.init(3,3)))
    }
    static func seed() async throws {
        let docs=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        let marker=docs.appendingPathComponent("qa-seeded")
        guard !FileManager.default.fileExists(atPath:marker.path) else {return}
        for folder in ["Scans","PerformancePlans","GuidanceRecords","PlaceFolders"] {try? FileManager.default.removeItem(at:docs.appendingPathComponent(folder))}
        let library=StageLibrary(),r=try route(),frame=try StageFrame(origin:r.area.world(.init(0,0)),front:r.area.world(.init(0,-1)))
        let mesh=MeshSnapshot(id:UUID(),transform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],vertices:[.init(0,0,0),.init(6,0,0),.init(6,0,-4),.init(0,0,-4),.init(6,3,-4),.init(0,3,-4)],indices:[0,1,2,0,2,3,3,2,4,3,4,5])
        for (i,n) in ["Look at me","Look at me","중앙무대"].enumerated() {
            _=try await library.scans.save(id:ids[i],name:n,frame:frame,checkpoint:r.area.world(.init(1,3)),worldMap:Data([1]),meshes:[mesh],device:"UI 예시",appVersion:"86",route:r,secondCheckpoint:r.area.world(.init(3,3)))
        }
        let places=PlaceFolderStore(root:docs.appendingPathComponent("PlaceFolders"))
        let data=(UIImage(named:"StageEmpty") ?? UIImage(systemName:"building.2")!).jpegData(compressionQuality:0.9)!
        _=try await places.upsert(rehearsal,photo:data);_=try await places.upsert(theater,photo:data)
        _=try await places.assign([ids[0]],to:.init(placeID:rehearsal.id,folderID:rehearsal.folders[0].id))
        _=try await places.assign([ids[1]],to:.init(placeID:theater.id))
        var plan=PerformancePlan();plan.name="Look at me"
        for p in [FloorPoint(-1,2),.init(2,2),.init(5,5),.init(9,5),.init(13,4)] {try plan.append(p)}
        try plan.finishRoute();try await library.planStore.save(plan)
        try await library.saveGuidanceRecord(record())
        try Data([1]).write(to:marker)
    }
    static func record() throws -> GuidanceRecord {
        let r=try route(),start=Date(timeIntervalSince1970:1793055600)
        let samples=(0...180).map {i -> GuidanceReplaySample in
            let t=Double(i)*0.2,progress=min(4,t/36*4),s=min(3,Int(progress)),f=progress-Double(s)
            let a=r.points[s],b=r.points[s+1],p=FloorPoint(a.x+(b.x-a.x)*f,a.y+(b.y-a.y)*f+(t>22 && t<26 ? 0.6:0))
            return .init(time:t,position:t>16 && t<18 ? nil:p,heading:t>16 && t<18 ? nil:180,targetIndex:s+1,status:t>16 && t<18 ? .untracked:t>22 && t<26 ? .offRoute:.guiding)
        }
        return GuidanceRecord(version:2,id:ids[0],stageID:ids[1],stageName:"Look at me",route:r,startedAt:start,completedAt:start.addingTimeInterval(36),finishedAt:start.addingTimeInterval(36),activeSeconds:34,replay:.init(duration:36,samples:samples))
    }
}
