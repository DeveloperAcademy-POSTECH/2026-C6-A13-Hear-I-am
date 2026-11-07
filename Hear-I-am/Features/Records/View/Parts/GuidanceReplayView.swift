import SwiftUI
import Combine
import HearIAmCore

/// Figma 971:31085 · 971:31135 · 971:31745: the recorded run fills the page and plays like a video. A glass bar
/// at the bottom holds play/pause and the timeline, with a dot under it at every arrival; touching the timeline
/// hides the button and shows the elapsed and remaining time on both sides, as in Photos, and dragging moves the
/// play head from where it was. The speaker button beside it reads each arrival aloud as the play head passes it.
struct GuidanceReplayView: View {
    @StateObject private var player: GuidanceReplayPlayer
    @Environment(\.scenePhase) private var scenePhase
    @State private var speech=GuidanceSpeech()
    @State private var muted=false
    @State private var scrubbing=false
    @State private var scrubStart=0.0
    @State private var trackWidth: CGFloat=0
    let sceneChip: AnyView
    let onDelete: (() -> Void)?
    private let timer=Timer.publish(every:1.0/30,on:.main,in:.common).autoconnect()
    private static let barSpring=Animation.spring(duration:0.3,bounce:0.15)
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
            HStack(alignment:.bottom,spacing:6) {
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

    private var timeline: some View {
        HStack(spacing:10) {
            if !scrubbing {
                Button {
                    if player.isPlaying {player.pause();speech.stop()} else {player.play()}
                } label: {
                    Image(systemName:player.isPlaying ? "pause.fill" : "play.fill").font(.system(size:17,weight:.semibold))
                        .foregroundStyle(.white).contentTransition(.symbolEffect(.replace))
                        .frame(width:44,height:44).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(player.replay.duration<=0)
                    .accessibilityLabel(player.isPlaying ? "일시정지" : "재생")
                    .transition(.opacity.combined(with:.scale(scale:0.5)))
            }
            VStack(spacing:8) {
                if scrubbing {
                    HStack {
                        Text(Self.clock(player.time))
                        Spacer()
                        Text("−"+Self.clock(player.replay.duration-player.time))
                    }.font(.system(size:11)).monospacedDigit().foregroundStyle(Color(red:235/255,green:235/255,blue:245/255).opacity(0.7))
                        .frame(height:13).transition(.opacity)
                }
                track
            }.frame(maxWidth:.infinity).frame(height:44).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:0).onChanged {value in
                    if !scrubbing {
                        scrubStart=player.time;player.scrub(true);speech.stop()
                        withAnimation(Self.barSpring) {scrubbing=true}
                    }
                    guard trackWidth>0 else {return}
                    player.seek(scrubStart+Double(value.translation.width/trackWidth)*player.replay.duration)
                }.onEnded {_ in
                    player.scrub(false)
                    withAnimation(Self.barSpring) {scrubbing=false}
                })
                .accessibilityElement(children:.ignore).accessibilityLabel("재생 위치")
                .accessibilityValue("\(Self.clock(player.time)), 전체 \(Self.clock(player.replay.duration))")
                .accessibilityAdjustableAction {direction in
                    switch direction {
                    case .increment: player.seek(player.time+5)
                    case .decrement: player.seek(player.time-5)
                    @unknown default: break
                    }
                }
        }.padding(.leading,scrubbing ? 18 : 8).padding(.trailing,scrubbing ? 18 : 16)
            .frame(height:scrubbing ? 54 : 50)
            .liquidGlass(Capsule(),tint:.white.opacity(0.05),interactive:true)
            .padding(.leading,scrubbing ? -5 : 0)
    }
    /// The played part in white over the whole length at 18%, thicker while it is being dragged, with a dot under it
    /// at every arrival: bright once played, dim ahead.
    private var track: some View {
        let duration=max(player.replay.duration,0.001)
        let height: CGFloat=scrubbing ? 7 : 4
        return ZStack(alignment:.leading) {
            Capsule().fill(.white.opacity(0.18))
            Capsule().fill(.white.opacity(0.9)).frame(width:max(height,trackWidth*min(1,player.time/duration)))
        }.frame(height:height)
            .onGeometryChange(for:CGFloat.self) {$0.size.width} action: {trackWidth=$0}
            .overlay(alignment:.topLeading) {
                ForEach(tickTimes,id:\.self) {time in
                    Circle().fill(.white.opacity(time<=player.time ? 0.9 : 0.4)).frame(width:3,height:3)
                        .offset(x:trackWidth*time/duration-1.5,y:height+4)
                }
            }
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
                .frame(width:50,height:50).liquidGlass(Circle(),tint:.white.opacity(0.05),interactive:true).contentShape(Circle())
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
