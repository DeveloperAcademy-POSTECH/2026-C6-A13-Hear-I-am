import SwiftUI
import Combine
import HearIAmCore

/// Figma 971:31085 · 971:31135 · 971:31745: the recorded run fills the page and plays like a video. A glass bar
/// at the bottom holds play/pause and the system slider, with a tick under it at every arrival; touching the slider
/// shows the elapsed and remaining time on both sides, as in Photos. The speaker button beside it reads each arrival aloud as the play head passes it.
struct GuidanceReplayView: View {
    @StateObject private var player: GuidanceReplayPlayer
    @Environment(\.scenePhase) private var scenePhase
    @State private var speech=GuidanceSpeech()
    @State private var muted=false
    @State private var scrubbing=false
    let sceneChip: AnyView
    let onDelete: (() -> Void)?
    private let timer=Timer.publish(every:1.0/30,on:.main,in:.common).autoconnect()
    init(record: GuidanceRecord,replay: GuidanceReplay,sceneChip: AnyView,onDelete: (() -> Void)?) {
        _player=StateObject(wrappedValue:GuidanceReplayPlayer(record:record,replay:replay))
        self.sceneChip=sceneChip;self.onDelete=onDelete
    }
    var body: some View {
        ZStack {
            Color(GuidanceReplayScene.background).ignoresSafeArea()
            GuidanceReplaySceneView(player:player).ignoresSafeArea()
                .accessibilityLabel("저장된 경로와 실제로 걸은 길을 다시 보는 3D 화면. 한 손가락으로 돌리고 두 손가락으로 옮기거나 확대해요.")
        }
        .overlay(alignment:.bottom) {
            HStack(spacing:8) {
                timeline
                speakerButton
            }.padding(.horizontal,16)
        }
        .hearTopBar(center:{sceneChip}) {HearBackButton()} trailing: {moreMenu}
        .preferredColorScheme(.dark)
        .onReceive(timer) {_ in player.advance()}
        .onChange(of:player.time) {old,new in narrate(from:old,to:new)}
        .onChange(of:scenePhase) {_,phase in if phase != .active {player.pause();speech.stop()}}
        .onAppear {
            player.play()
            #if DEBUG
            let args=ProcessInfo.processInfo.arguments
            if let index=args.firstIndex(of:"--record-time"),args.count>index+1,let value=Double(args[index+1]) {player.pause();player.seek(value)}
            if args.contains("--record-top") {player.cameraMode = .overhead}
            if args.contains("--record-muted") {muted=true}
            if args.contains("--record-scrubbing") {scrubbing=true}
            #endif
        }
        .onDisappear {player.pause();speech.deactivate()}
        .suspendsVoiceWake()
    }

    // MARK: Bottom bar

    /// The play button and the system slider in one glass capsule that never changes size, so nothing moves under
    /// the finger. Touching the slider fades the elapsed and remaining time in above its two ends, as in Photos.
    private var timeline: some View {
        HStack(spacing:6) {
            Button {
                if player.isPlaying {player.pause();speech.stop()} else {player.play()}
            } label: {
                Image(systemName:player.isPlaying ? "pause.fill" : "play.fill").font(.system(size:17,weight:.semibold))
                    .foregroundStyle(.white).contentTransition(.symbolEffect(.replace))
                    .frame(width:44,height:44).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(player.replay.duration<=0)
                .accessibilityLabel(player.isPlaying ? "일시정지" : "재생")
            slider
                .overlay(alignment:.top) {
                    HStack {
                        Text(Self.clock(player.time))
                        Spacer()
                        Text("−"+Self.clock(player.replay.duration-player.time))
                    }.font(.system(size:11)).monospacedDigit().foregroundStyle(Color(red:235/255,green:235/255,blue:245/255).opacity(0.7))
                        .offset(y:-6).opacity(scrubbing ? 1 : 0).allowsHitTesting(false).accessibilityHidden(true)
                }
        }.padding(.leading,8).padding(.trailing,16).frame(height:54)
            // Not interactive: interactive glass swells under a touch, which pushed the bar into the speaker.
            .liquidGlass(Capsule(),tint:.white.opacity(0.05),interactive:false)
    }
    /// Figma 971:31743: the iOS 26 slider with a tick under it at every arrival; earlier systems get the plain slider.
    @ViewBuilder private var slider: some View {
        let duration=max(player.replay.duration,0.001)
        let value=Binding(get:{min(player.time,duration)},set:{player.seek($0)})
        if #available(iOS 26.0, *) {
            Slider(value:value,in:0...duration,label:{Text("재생 위치")},ticks:{
                SliderTickContentForEach(tickTimes,id:\.self) {SliderTick($0)}
            },onEditingChanged:editing)
                .tint(.white).frame(maxWidth:.infinity)
                .accessibilityValue("\(Self.clock(player.time)), 전체 \(Self.clock(player.replay.duration))")
        } else {
            Slider(value:value,in:0...duration,label:{Text("재생 위치")},onEditingChanged:editing)
                .tint(.white).frame(maxWidth:.infinity)
                .accessibilityValue("\(Self.clock(player.time)), 전체 \(Self.clock(player.replay.duration))")
        }
    }
    private func editing(_ active: Bool) {
        player.scrub(active)
        if active {speech.stop()}
        withAnimation(.easeOut(duration:0.2)) {scrubbing=active}
    }
    /// Arrivals and the last arrival, the moments the narration speaks.
    private var tickTimes: [Double] {
        Array(Set(player.analysis.events.compactMap {event -> Double? in
            switch event.kind {case .arrival,.finish: event.time; default: nil}
        })).sorted()
    }
    private var speakerButton: some View {
        Button {
            muted.toggle()
            if muted {speech.stop()}
        } label: {
            Image(systemName:muted ? "speaker.slash" : "speaker.wave.2.fill").font(.system(size:15,weight:.semibold))
                .foregroundStyle(.white).contentTransition(.symbolEffect(.replace))
                .frame(width:54,height:54).liquidGlass(Circle(),tint:.white.opacity(0.05),interactive:true).contentShape(Circle())
        }.buttonStyle(.plain).accessibilityLabel(muted ? "소리 켜기" : "소리 끄기")
            .accessibilityHint("재생하면서 지점 도착과 경로 이탈을 읽어 줘요.")
    }

    // MARK: ⋯ menu (971:31656)

    private var moreMenu: some View {
        Menu {
            Button {player.cameraMode = .overview;player.cameraRevision+=1} label: {Label("시점 초기화",systemImage:"arrow.counterclockwise")}
            Button {player.cameraMode=player.cameraMode == .overhead ? .overview : .overhead} label: {
                Label(player.cameraMode == .overhead ? "기본 시점으로 보기" : "동선 위에서 보기",systemImage:"eye")
            }
            if let onDelete {
                Divider()
                Button(role:.destructive,action:onDelete) {Label("현재 기록 삭제",systemImage:"trash")}
            }
        } label: {HearTopButtonLabel(systemImage:"ellipsis")}
            .buttonStyle(.plain).accessibilityLabel("기록 메뉴")
    }

    // MARK: Narration

    /// While playing forward at normal speed, say the last moment the play head just passed. Seeks and scrubbing
    /// jump further than a frame and stay quiet.
    private func narrate(from old: Double,to new: Double) {
        guard !muted,player.isPlaying,new>old,new-old<1 else {return}
        guard let event=player.analysis.events.last(where:{$0.time>old && $0.time<=new}),let line=spokenLine(event) else {return}
        speech.play([line])
    }
    private func spokenLine(_ event: GuidanceReplayEvent) -> String? {
        switch event.kind {
        case .arrival(let index): return "\(player.record.route.pointLabel(at:index)) 도착"
        case .finish: return "마지막 지점 도착"
        case .status(let status):
            switch status {
            case .offRoute,.outsideStage,.obstacle: return status.title
            default: return nil
            }
        case .start: return nil
        }
    }
    /// 「0:21」 as in Photos; hours from an hour.
    static func clock(_ seconds: Double) -> String {
        let value=Int(max(0,seconds).rounded(.down))
        return value>=3600 ? String(format:"%d:%02d:%02d",value/3600,(value/60)%60,value%60) : String(format:"%d:%02d",value/60,value%60)
    }
}
