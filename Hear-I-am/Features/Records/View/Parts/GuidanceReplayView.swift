import SwiftUI
import Combine
import HearIAmCore

/// Figma 971:31085 · 971:31135 · 971:31745: the recorded run fills the page and plays like a video. A glass bar
/// at the bottom works like the Photos video bar, with a dot under the track at every arrival; the speaker sits
/// beside it. The speaker button beside it reads each arrival aloud as the play head passes it.
struct GuidanceReplayView: View {
    @StateObject private var player: GuidanceReplayPlayer
    @Environment(\.scenePhase) private var scenePhase
    @State private var speech=GuidanceSpeech()
    @State private var muted=false
    @State private var scrubbing=false
    @State private var scrubStart=0.0
    @State private var trackWidth: CGFloat=0
    @GestureState private var dragging=false
    private static let barSpring=Animation.spring(duration:0.42,bounce:0.18)
    let sceneChip: AnyView
    let onDelete: (() -> Void)?
    private let timer=Timer.publish(every:1.0/60,on:.main,in:.common).autoconnect()
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
            glassGroup {
                HStack(alignment:.bottom,spacing:8) {
                    timeline
                    if !scrubbing {
                        speakerButton.transition(.scale(scale:0.2,anchor:.leading).combined(with:.opacity))
                    }
                }
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
            // Lets go of a held bar after three seconds, to check the bar settles back to its resting width.
            if args.contains("--record-release") {
                DispatchQueue.main.asyncAfter(deadline:.now()+3) {withAnimation(Self.barSpring) {scrubbing=false}}
            }
            #endif
        }
        .onDisappear {player.pause();speech.deactivate()}
        .suspendsVoiceWake()
    }

    // MARK: Bottom bar

    /// The Photos video bar (Figma 971:31085 · 971:31135): play/pause and a thin track in one glass capsule. Touching
    /// the track runs one spring: the play button shrinks away, the bar stretches over the speaker's place as the
    /// speaker shrinks out, grows a little taller, the track thickens and the elapsed and remaining time rise in
    /// above it. Letting go runs it back. Dragging moves the play head by how far the finger went, from where it
    /// was, and stops anywhere; passing an arrival dot gives a light tick in the hand.
    private var timeline: some View {
        HStack(spacing:12) {
            if !scrubbing {
                Button {
                    if player.isPlaying {player.pause();speech.stop()} else {player.play()}
                } label: {
                    Image(systemName:player.isPlaying ? "pause.fill" : "play.fill").font(.system(size:17,weight:.semibold))
                        .foregroundStyle(.white).contentTransition(.symbolEffect(.replace))
                        .frame(width:44,height:44).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(player.replay.duration<=0)
                    .accessibilityLabel(player.isPlaying ? "일시정지" : "재생")
                    .transition(.scale(scale:0.2,anchor:.leading).combined(with:.opacity))
            }
            track
                .frame(maxWidth:.infinity,maxHeight:.infinity).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:0)
                    .updating($dragging) {_,state,_ in state=true}
                    .onChanged {value in
                        if !scrubbing {
                            scrubStart=player.time;player.scrub(true);speech.stop()
                            withAnimation(Self.barSpring) {scrubbing=true}
                        }
                        guard trackWidth>0 else {return}
                        player.seek(scrubStart+Double(value.translation.width/trackWidth)*player.replay.duration)
                    })
                // @GestureState resets even when the system cancels the drag, so the bar never stays expanded.
                .onChange(of:dragging) {_,active in
                    guard !active,scrubbing else {return}
                    player.scrub(false)
                    withAnimation(Self.barSpring) {scrubbing=false}
                }
                .sensoryFeedback(.selection,trigger:passedTicks) {_,_ in scrubbing}
                .accessibilityElement(children:.ignore).accessibilityLabel("재생 위치")
                .accessibilityValue("\(Self.clock(player.time)), 전체 \(Self.clock(player.replay.duration))")
                .accessibilityAdjustableAction {direction in
                    switch direction {
                    case .increment: player.seek(player.time+5)
                    case .decrement: player.seek(player.time-5)
                    @unknown default: break
                    }
                }
        }.padding(.leading,scrubbing ? 24 : 10).padding(.trailing,scrubbing ? 24 : 22)
            .frame(height:scrubbing ? 64 : 50)
            // Not interactive: interactive glass swells under a touch on its own, out of step with this spring.
            .liquidGlass(Capsule(),tint:.white.opacity(0.05),interactive:false)
    }
    /// The played part in white over the whole length at 18%, centred in the capsule, with a dot under it at every
    /// arrival (971:31743), bright once passed and dim ahead, and the times above it while held. The played part and
    /// the dots are laid out from the track's own animated size, so they stretch along with it instead of jumping
    /// to the new width, and they never feed back into the track's size. Nothing is filled at the start.
    private var track: some View {
        let duration=max(player.replay.duration,0.001)
        let height: CGFloat=scrubbing ? 8 : 4
        let ratio=min(1,max(0,player.time/duration))
        return Capsule().fill(.white.opacity(scrubbing ? 0.24 : 0.18)).frame(height:height)
            .overlay(alignment:.leading) {
                GeometryReader {proxy in
                    Capsule().fill(.white.opacity(0.9))
                        .frame(width:proxy.size.width*ratio,height:proxy.size.height)
                        .opacity(ratio>0 ? 1 : 0)
                }
            }
            .overlay(alignment:.topLeading) {
                GeometryReader {proxy in
                    ForEach(tickTimes,id:\.self) {time in
                        Circle().fill(.white.opacity(time<=player.time && player.time>0 ? 0.8 : 0.35)).frame(width:4,height:4)
                            .position(x:proxy.size.width*time/duration,y:proxy.size.height+6)
                    }
                }
            }
            .overlay(alignment:.top) {
                HStack {
                    Text(Self.clock(player.time))
                    Spacer()
                    Text("−"+Self.clock(player.replay.duration-player.time))
                }.font(.system(size:11)).monospacedDigit().foregroundStyle(Color(red:235/255,green:235/255,blue:245/255).opacity(0.7))
                    .fixedSize(horizontal:false,vertical:true)
                    .offset(y:scrubbing ? -20 : -12).opacity(scrubbing ? 1 : 0)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .onGeometryChange(for:CGFloat.self) {$0.size.width} action: {trackWidth=$0}
    }
    /// On iOS 26 the bar and the speaker share one glass container. Resting 8 pt apart they stay two shapes; the
    /// shrinking speaker comes within 4 pt and melts into the stretching bar, and drips back out on release.
    @ViewBuilder private func glassGroup(@ViewBuilder _ content: () -> some View) -> some View {
        if #available(iOS 26, *) {GlassEffectContainer(spacing:4) {content()}} else {content()}
    }
    /// How many arrival dots the play head has passed; a change while scrubbing ticks the haptic.
    private var passedTicks: Int {tickTimes.filter {$0<=player.time}.count}
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
