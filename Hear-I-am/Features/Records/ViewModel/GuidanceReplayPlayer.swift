import Foundation
import Combine
import HearIAmCore

@MainActor final class GuidanceReplayPlayer: ObservableObject {
    let record: GuidanceRecord,replay: GuidanceReplay,analysis: GuidanceReplayAnalysis
    let scene: GuidanceReplayScene
    @Published private(set) var time=0.0
    @Published private(set) var isPlaying=false
    @Published private(set) var rate=1.0
    @Published var cameraMode: ReplayCamera = .overview
    @Published var cameraRevision=0
    private var anchorTime=0.0,anchorUptime=0.0
    private var resumeAfterScrub=false
    init(record: GuidanceRecord,replay: GuidanceReplay) {
        self.record=record;self.replay=replay;self.analysis=GuidanceReplayAnalysis(replay:replay,route:record.route)
        scene=GuidanceReplayScene(record:record)
    }
    var pose: GuidanceReplaySample? {replay.pose(at:time)}
    var currentStatus: GuidanceReplayStatus {pose?.status ?? .untracked}
    var deviation: Double? {pose?.position.map {GuidanceReplayAnalysis.deviation($0,route:record.route)}}
    func play(at uptime: Double = ProcessInfo.processInfo.systemUptime) {
        guard replay.duration>0 else {return}
        if time>=replay.duration {time=0}
        anchorTime=time;anchorUptime=uptime;isPlaying=true
    }
    func pause() {isPlaying=false;resumeAfterScrub=false}
    func advance(to uptime: Double = ProcessInfo.processInfo.systemUptime) {
        guard isPlaying else {return}
        time=min(replay.duration,anchorTime+max(0,uptime-anchorUptime)*rate)
        if time>=replay.duration {isPlaying=false}
    }
    func seek(_ value: Double,at uptime: Double = ProcessInfo.processInfo.systemUptime) {
        guard value.isFinite else {return}
        time=max(0,min(replay.duration,value));anchorTime=time;anchorUptime=uptime
        if time>=replay.duration {isPlaying=false}
    }
    func setRate(_ value: Double,at uptime: Double = ProcessInfo.processInfo.systemUptime) {
        guard [0.5,1,2].contains(value) else {return}
        advance(to:uptime);rate=value;anchorTime=time;anchorUptime=uptime
    }
    func scrub(_ editing: Bool) {
        if editing {resumeAfterScrub=isPlaying;isPlaying=false}
        else {let resume=resumeAfterScrub;resumeAfterScrub=false;if resume,time<replay.duration {play()}}
    }
    static func clock(_ seconds: Double) -> String {
        let value=Int(max(0,seconds).rounded(.down))
        return value>=3600 ? String(format:"%d:%02d:%02d",value/3600,(value/60)%60,value%60) : String(format:"%02d:%02d",value/60,value%60)
    }
}

extension GuidanceReplayStatus {
    var title: String {
        switch self {
        case .guiding: return "이동 안내"
        case .paused: return "일시정지"
        case .offRoute: return "경로 이탈"
        case .outsideStage: return "무대 범위 밖"
        case .obstacle: return "기물 접근"
        case .recovering: return "위치 재확인"
        case .untracked: return "위치 기록 없음"
        }
    }
    var symbol: String {
        switch self {
        case .guiding: return "figure.walk"
        case .paused: return "pause.circle"
        case .offRoute,.outsideStage: return "arrow.triangle.branch"
        case .obstacle: return "exclamationmark.triangle"
        case .recovering,.untracked: return "location.slash"
        }
    }
}
