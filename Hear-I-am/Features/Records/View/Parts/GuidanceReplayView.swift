import SwiftUI
import HearIAmCore

struct GuidanceReplayView: View {
    @StateObject private var player: GuidanceReplayPlayer
    @Environment(\.scenePhase) private var scenePhase
    private let timer=Timer.publish(every:1.0/30,on:.main,in:.common).autoconnect()
    init(record: GuidanceRecord,replay: GuidanceReplay) {
        _player=StateObject(wrappedValue:GuidanceReplayPlayer(record:record,replay:replay))
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Picker("보는 방향",selection:$player.cameraMode) {
                ForEach(ReplayCamera.allCases,id:\.self) {Text($0.rawValue).tag($0)}
            }.pickerStyle(.segmented)
            GuidanceReplaySceneView(player:player)
                .frame(height:320).clipShape(RoundedRectangle(cornerRadius:24))
                .overlay(alignment:.topTrailing) {
                    Button {player.cameraRevision+=1} label: {
                        Image(systemName:"arrow.counterclockwise").font(.body.weight(.semibold))
                            .frame(width:44,height:44).background(.regularMaterial,in:Circle())
                    }.padding(12).accessibilityLabel("시점 초기화")
                }
                .overlay(alignment:.bottomLeading) {
                    Label(player.pose == nil ? "이 구간은 위치 기록이 없어요" : "사용자 위치 · 몸 방향",
                          systemImage:player.pose == nil ? "location.slash" : "figure.stand")
                        .font(.caption).padding(10).background(.regularMaterial,in:Capsule()).padding(12)
                        .allowsHitTesting(false)
                }.accessibilityElement(children:.contain)
                .accessibilityLabel("저장된 표준 경로와 실제 이동 궤적의 3D 화면")
            HStack(spacing:16) {
                HStack(spacing:5) {
                    Path {p in p.move(to:CGPoint(x:0,y:1));p.addLine(to:CGPoint(x:24,y:1))}.stroke(style:StrokeStyle(lineWidth:2,dash:[4,3])).frame(width:24,height:2)
                    Text("표준 경로")
                }.foregroundStyle(.secondary)
                HStack(spacing:5) {Capsule().fill(.blue).frame(width:23,height:3);Text("실제 이동")}
                Spacer(minLength:0)
            }.font(.caption)
            playback
            metrics
            VStack(alignment:.leading,spacing:10) {
                Text("주요 순간").font(.subheadline.bold())
                ScrollView(.horizontal,showsIndicators:false) {
                    LazyHStack(spacing:8) {
                        ForEach(player.analysis.events) {event in
                            Button {player.pause();player.seek(event.time)} label: {
                                VStack(alignment:.leading,spacing:5) {
                                    Text(eventTitle(event)).font(.caption.weight(.semibold))
                                    Text(GuidanceReplayPlayer.clock(event.time)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                                }.padding(.horizontal,12).padding(.vertical,10)
                                    .background(Color(.secondarySystemBackground),in:RoundedRectangle(cornerRadius:12))
                            }.buttonStyle(.plain).accessibilityLabel("\(eventTitle(event)), \(GuidanceReplayPlayer.clock(event.time)) 시점으로 이동")
                        }
                    }
                }
            }
            if player.analysis.missingSeconds>=1 {
                Label("위치 미기록 \(GuidanceReplayPlayer.clock(player.analysis.missingSeconds)) · 끊긴 구간은 이어 그리지 않아요",systemImage:"location.slash")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if player.replay.truncated {
                Text("기록 용량에 도달해 뒷부분의 위치가 저장되지 않았어요.").font(.caption).foregroundStyle(.orange)
            }
            Text("저장된 무대와 경로를 기준으로 재구성한 공간이에요. 인물은 기록된 위치와 몸 방향을 보여줘요. 높이는 저장된 경로를 기준으로 표시하며, 발걸음과 시선은 기록하지 않아요.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onReceive(timer) {_ in player.advance()}
        .onChange(of:scenePhase) {_,phase in if phase != .active {player.pause()}}
        .onDisappear {player.pause()}
        #if DEBUG
        .onAppear {
            if let index=ProcessInfo.processInfo.arguments.firstIndex(of:"--record-time"),ProcessInfo.processInfo.arguments.count>index+1,
               let value=Double(ProcessInfo.processInfo.arguments[index+1]) {player.seek(value)}
            if ProcessInfo.processInfo.arguments.contains("--record-top") {player.cameraMode = .overhead}
        }
        #endif
    }
    private var playback: some View {
        VStack(spacing:10) {
            HStack(alignment:.firstTextBaseline) {
                Label(player.time>=player.replay.duration ? "안내 완료" : player.currentStatus.title,
                      systemImage:player.time>=player.replay.duration ? "checkmark.circle" : player.currentStatus.symbol)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength:8)
                if let pose=player.pose,player.time<player.replay.duration {
                    Text("\(pose.targetIndex+1)번 지점으로").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                if let deviation=player.deviation {Text(String(format:"표준 경로에서 %.2f m",deviation))}
                else {Text("경로 이격 —")}
                Spacer()
            }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Slider(value:Binding(get:{player.time},set:{player.seek($0)}),in:0...max(player.replay.duration,0.001),onEditingChanged:player.scrub)
                .tint(.hearGreen).disabled(player.replay.duration<=0)
                .accessibilityLabel("재생 위치").accessibilityValue("\(GuidanceReplayPlayer.clock(player.time)), 전체 \(GuidanceReplayPlayer.clock(player.replay.duration))")
            HStack {
                Text(GuidanceReplayPlayer.clock(player.time))
                Spacer()
                Text(GuidanceReplayPlayer.clock(player.replay.duration))
            }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
            HStack {
                Button {player.pause();player.seek(0)} label: {Image(systemName:"backward.end.fill").frame(width:44,height:44)}
                    .accessibilityLabel("처음으로")
                Spacer()
                Button {if player.isPlaying {player.pause()} else {player.play()}} label: {
                    Image(systemName:player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3).foregroundStyle(.white).frame(width:56,height:48).background(Color.hearGreen,in:Capsule())
                }.accessibilityLabel(player.isPlaying ? "일시정지" : "재생").disabled(player.replay.duration<=0)
                Spacer()
                Menu {
                    ForEach([0.5,1.0,2.0],id:\.self) {rate in
                        Button {player.setRate(rate)} label: {
                            HStack {Text("\(rate.formatted())배속");if player.rate==rate {Image(systemName:"checkmark")}}
                        }
                    }
                } label: {Text("\(player.rate.formatted())×").font(.subheadline.bold()).frame(width:44,height:44)}
                    .accessibilityLabel("재생 속도 \(player.rate.formatted())배")
            }
        }.padding(16).background(Color(.secondarySystemBackground),in:RoundedRectangle(cornerRadius:20))
    }
    private var metrics: some View {
        VStack(alignment:.leading,spacing:10) {
            ViewThatFits(in:.horizontal) {
                HStack(alignment:.top,spacing:0) {metricItems}
                VStack(alignment:.leading,spacing:12) {metricItems}
            }
            Text(String(format:"표준 경로 %.1f m · %d개 지점 도착",player.record.routeLength,player.record.reachedPointCount))
                .font(.caption).foregroundStyle(.secondary)
            Text("안내 시간은 정지·재확인 시간을 제외해요. 이동 거리와 최대 이격은 추적 오차가 포함된 추정값이에요.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var metricItems: some View {
        metric("안내 시간",player.record.activeDurationText)
        metric("추정 이동",String(format:"%.1f m",player.analysis.distance))
        metric("최대 이격",String(format:"%.2f m",player.analysis.maximumDeviation))
    }
    private func metric(_ title: String,_ value: String) -> some View {
        VStack(alignment:.leading,spacing:6) {Text(title).font(.caption).foregroundStyle(.secondary);Text(value).font(.headline).monospacedDigit()}
            .frame(maxWidth:.infinity,alignment:.leading)
    }
    private func eventTitle(_ event: GuidanceReplayEvent) -> String {
        switch event.kind {
        case .start: return "출발"
        case .arrival(let index): return "\(index+1)번 도착"
        case .status(let status): return status.title
        case .finish: return "마지막 도착"
        }
    }
}
