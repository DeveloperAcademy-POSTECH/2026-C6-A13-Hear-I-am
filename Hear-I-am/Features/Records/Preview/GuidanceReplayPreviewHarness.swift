#if DEBUG
import SwiftUI
import SceneKit
import HearIAmCore

/// Synthetic data only. This entry point never writes to the user's stage or record stores.
struct GuidanceReplayPreviewHarness: View {
    @State private var record: GuidanceRecord?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            if let record {GuidanceRecordDetail(record:record)}
            else if let error {Text(error)}
            else {ProgressView().task {prepare()}}
        }.tint(.hearGreen)
    }
    @MainActor private func prepare() {
        do {
            let fixture=try makeRecord()
            try fixture.validate()
            try verify(fixture)
            if ProcessInfo.processInfo.arguments.contains("--record-legacy") {
                record=GuidanceRecord(version:1,id:fixture.id,stageID:fixture.stageID,stageName:fixture.stageName,route:fixture.route,
                    startedAt:fixture.startedAt,completedAt:fixture.completedAt,finishedAt:fixture.finishedAt,activeSeconds:fixture.activeSeconds)
            } else {record=fixture}
            print("GUIDANCE_REPLAY_QA_OK: clock, rate, scrubbing, end, gaps, saved height, heading, camera reset, bundled figure, legacy compatibility")
        } catch {self.error=error.localizedDescription;print("GUIDANCE_REPLAY_QA_FAILED: \(error)")}
    }
    private func makeRecord() throws -> GuidanceRecord {
        let area=try StageArea(corners:[.init(0,0,0),.init(6,0,0),.init(6,0,-4),.init(0,0,-4)])
        let table=try StageObstacle(name:"테이블",kind:.other,vertices:[.init(0.5,2.5),.init(1.6,2.5),.init(1.6,3.2),.init(0.5,3.2)],height:0.75,appearance:.init(model:.table))
        let chair=try StageObstacle(name:"의자",kind:.other,vertices:[.init(4.8,1),.init(5.4,1),.init(5.4,1.6),.init(4.8,1.6)],height:0.85,appearance:.init(model:.chair))
        let route=try StageRoute(area:area,points:[.init(1,0.4),.init(2.3,1.4),.init(3.4,2.3),.init(5,3.4)],obstacles:[table,chair],pointHeights:[0,0,0,0])
        var samples=[GuidanceReplaySample]()
        for i in 0...180 {
            let t=Double(i)*0.2
            let progress=max(0,min(3,(t-max(0,min(2,t-8)))/34*3))
            let segment=min(2,Int(progress)),fraction=min(1,progress-Double(segment))
            let a=route.points[segment],b=route.points[segment+1]
            let offset=(t>=24 && t<=28) ? sin((t-24)/4 * .pi)*0.7 : sin(progress*4)*0.09
            let p=FloorPoint(a.x+(b.x-a.x)*fraction,a.y+(b.y-a.y)*fraction+offset)
            let heading=atan2(-(b.x-a.x),-(b.y-a.y))*180 / .pi
            let missing=t>=18 && t<20
            let status: GuidanceReplayStatus=missing ? .untracked : t>=8 && t<10 ? .paused : t>=25 && t<27 ? .offRoute : .guiding
            samples.append(.init(time:t,position:missing ? nil:p,heading:missing ? nil:heading,targetIndex:segment+1,status:status))
        }
        let start=Date(timeIntervalSince1970:1_792_540_800)
        return GuidanceRecord(version:2,id:UUID(),stageID:UUID(),stageName:"중앙무대 · 검증용 기록",route:route,
            startedAt:start,completedAt:start.addingTimeInterval(36),finishedAt:start.addingTimeInterval(38),activeSeconds:30,
            replay:GuidanceReplay(duration:36,samples:samples))
    }
    @MainActor private func verify(_ record: GuidanceRecord) throws {
        func check(_ condition: Bool,_ message: String) throws {if !condition {throw LabError.invalid(message)}}
        let replay=record.replay!,player=GuidanceReplayPlayer(record:record,replay:replay)
        player.play(at:100);player.advance(to:101)
        try check(abs(player.time-1)<0.0001,"Playback clock")
        player.setRate(2,at:101);player.advance(to:102)
        try check(abs(player.time-3)<0.0001,"Playback rate continuity")
        player.pause();player.advance(to:110)
        try check(player.time==3 && !player.isPlaying,"Pause")
        player.seek(12,at:110);player.play(at:110);player.scrub(true);player.seek(20)
        try check(!player.isPlaying && player.time==20,"Scrub holds playback")
        player.scrub(false);try check(player.isPlaying,"Scrub resumes")
        player.pause();player.seek(100)
        try check(player.time==36 && !player.isPlaying,"Clamped end")
        player.play(at:200);try check(player.time==0 && player.isPlaying,"Replay after end")
        player.advance(to:300);try check(player.time==36 && !player.isPlaying,"Automatic end")
        let controller=player.scene,view=SCNView(frame:CGRect(x:0,y:0,width:360,height:320))
        view.scene=controller.scene;controller.view=view;view.allowsCameraControl=true
        controller.update(time:13,mode:.overview,revision:0)
        let original=controller.camera.simdTransform
        let pose=replay.pose(at:13)!,p=pose.position!
        try check(abs(controller.person.position.x-Float(p.x))<0.001 && abs(controller.person.position.z+Float(p.y))<0.001,"Recorded coordinates")
        try check(abs(controller.person.eulerAngles.y-Float(-pose.heading! * .pi/180))<0.001,"Body heading")
        let vertexCount=controller.person.childNodes.reduce(0) {$0+($1.geometry?.sources(for:.vertex).first?.vectorCount ?? 0)}
        try check(vertexCount>1000,"Bundled figure missing")
        controller.update(time:19,mode:.overview,revision:0)
        try check(controller.person.isHidden,"Tracking gap must hide figure")
        let during=controller.camera.simdTransform
        try check(simd_length(original.columns.3-during.columns.3)<0.0001,"Scrubbing moved camera")
        for i in 1...3 {
            controller.update(time:30,mode:.overhead,revision:i*2)
            controller.update(time:30,mode:.overview,revision:i*2+1)
        }
        let returned=controller.camera.simdTransform
        for i in 0..<4 {try check(simd_length(original[i]-returned[i])<0.0001,"Camera round trip")}
        // Exercise actual drag limits; SceneKit's getter returns radians even though its setter takes degrees.
        let controls=view.defaultCameraController,origin=CGPoint(x:180,y:160)
        for mode in ReplayCamera.allCases {
            controller.update(time:13,mode:mode,revision:20)
            for delta: CGFloat in [-2000,2000] {
                for _ in 0..<4 {
                    let end=CGPoint(x:200,y:origin.y+delta)
                    controls.beginInteraction(origin,withViewport:view.bounds.size)
                    controls.continueInteraction(end,withViewport:view.bounds.size,sensitivity:1)
                    controls.endInteraction(end,withViewport:view.bounds.size,velocity:.zero)
                    let forward=simd_act(controller.camera.simdWorldOrientation,SIMD3<Float>(0,0,-1))
                    let elevation=asin(max(-1,min(1,-forward.y)))*180 / .pi
                    try check(elevation>=14.99 && elevation<=90.01,"Camera orbit went below floor")
                }
            }
        }
        controls.translateInCameraSpaceBy(x:1,y:1,z:0);controls.dolly(toTarget:0.5)
        controller.update(time:13,mode:.overview,revision:21)
        for i in 0..<4 {try check(simd_length(original[i]-controller.camera.simdTransform[i])<0.0001,"Camera reset after pan/zoom")}

        let heights=try StageRoute(area:record.route.area,points:record.route.points,obstacles:[],pointHeights:[0,0.4,0.4,0])
        let elevated=GuidanceRecord(version:2,id:record.id,stageID:record.stageID,stageName:record.stageName,route:heights,
            startedAt:record.startedAt,completedAt:record.completedAt,finishedAt:record.finishedAt,activeSeconds:30,replay:replay)
        let lifted=GuidanceReplayScene(record:elevated)
        let a=heights.points[0],b=heights.points[1]
        try check(abs(lifted.height(.init((a.x+b.x)/2,(a.y+b.y)/2),target:1)-0.2)<0.0001,"Saved route height")
        let full=controller.scene.rootNode.childNode(withName:"record-entire-trace",recursively:true)!
        let played=controller.scene.rootNode.childNode(withName:"record-played-trace",recursively:true)!
        controller.show(time:0);try check(played.isHidden,"Zero played trace")
        controller.show(time:36)
        try check(played.geometry!.elements[0].primitiveRange.length==full.geometry!.elements[0].primitiveCount,"Completed trace range")
        try check(player.analysis.missingSeconds>=2 && player.analysis.events.contains {$0.kind == .status(.offRoute)},"Event and gap summary")
        let decoded=try JSONDecoder().decode(GuidanceRecord.self,from:JSONEncoder().encode(record))
        try check(decoded==record,"Serialized replay")
    }
}
#endif
