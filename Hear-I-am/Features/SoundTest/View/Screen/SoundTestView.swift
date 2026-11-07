import SwiftUI
import AVFoundation
import HearIAmCore

/// 「안내 신호 익히기」 (Figma 457:13480 · 13846 · 13950): the connected device, the output picker and the lessons.
/// Lives inside Settings, not a tab or a nested NavigationStack.
struct SoundTestView: View {
    @StateObject private var output=SoundOutputStatus()
    private var lessons: [SoundTestSection] {SoundTestSection.allCases.filter {$0 != .preparation}}
    var body: some View {
        ScrollView {
            VStack(spacing:8) {
                OutputDeviceHero(output:output)
                OutputDeviceRow(output:output).readAloudTarget("출력 기기, \(output.name)")
                VStack(spacing:0) {
                    SettingsSectionHeader(title:"음성 안내 리스트",size:15).padding(.top,8)
                    SettingsGroup {
                        ForEach(lessons) { step in
                            if step != lessons.first {SettingsDivider()}
                            NavigationLink {SignalLessonView(step:step)} label: {
                                SettingsRowLabel(title:step.title,detail:step.subtitle)
                            }.buttonStyle(.plain).readAloudTarget("\(step.title), \(step.subtitle)")
                                .accessibilityLabel("\(step.title), \(step.subtitle)")
                                .accessibilityIdentifier("tutorial.step.\(step.id)")
                        }
                    }
                }
            }.padding(.horizontal,16).padding(.bottom,16)
        }.settingsBottomBar {
            NavigationLink {SignalLessonView(step:.preparation)} label: {SettingsCapsuleLabel(title:"안내 신호 차례대로 익히기")}
                .buttonStyle(.plain).readAloudTarget("안내 신호 차례대로 익히기 버튼").accessibilityIdentifier("tutorial.start")
        }
        .settingsScreen()
        .navigationTitle("안내 신호 익히기").navigationBarTitleDisplayMode(.inline)
        .readsAloud(title:"안내 신호 익히기") {
            var lines=["안내 신호 익히기","연결된 기기, \(output.name)","출력 기기, \(output.name)","음성 안내 리스트"]
            lines.append(contentsOf:lessons.map {"\($0.title), \($0.subtitle)"})
            lines.append("안내 신호 차례대로 익히기 버튼")
            return lines
        }
        .onAppear {output.refresh()}
    }
}

/// One lesson page. 「듣기 준비」 is the volume page (Figma 457:13574); the others list their sounds
/// (457:13690 · 13738 · 13772 · 13809). The toolbar's speaker button reads the page aloud.
struct SignalLessonView: View {
    @State var step: SoundTestSection
    @StateObject private var model=SoundTestViewModel()
    @StateObject private var volume=VolumeWatcher()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AccessibilityFocusState private var headingFocused: Bool
    /// Which way the last page change went, so the new page slides in from that side.
    @State private var forward=true
    private var lessons: [SoundTestSection] {SoundTestSection.allCases.filter {$0 != .preparation}}
    /// Moves to another page, sliding it in from the side it lies on (11/07).
    private func go(to next: SoundTestSection) {
        model.stop()
        let all=SoundTestSection.allCases
        forward=(all.firstIndex(of:next) ?? 0) > (all.firstIndex(of:step) ?? 0)
        withAnimation(.snappy(duration:0.3)) {step=next}
    }
    /// A sideways swipe on a lesson moves between the four lessons the dots count; vertical drags still scroll.
    private var lessonSwipe: some Gesture {
        DragGesture(minimumDistance:24).onEnded {value in
            let dx=value.translation.width, dy=value.translation.height
            guard step != .preparation, abs(dx) > 60, abs(dx) > abs(dy)*1.5 else {return}
            if dx < 0, let next=step.next {go(to:next)}
            else if dx > 0, let previous=step.previous, previous != .preparation {go(to:previous)}
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing:0) {
                    Color.clear.frame(height:0).id("lesson-top")
                    Group {
                        if step == .preparation {volumePage} else {lessonPage}
                    }.padding(.horizontal,16).padding(.bottom,16)
                        .id(step).transition(.push(from:forward ? .trailing : .leading))
                }
            }
            .simultaneousGesture(lessonSwipe)
            .onChange(of:step) {_,_ in
                model.stop();model.clearError();proxy.scrollTo("lesson-top",anchor:.top);headingFocused=true
            }
        }
        .settingsBottomBar {
            if step == .preparation {
                SettingsCapsuleButton(title:"넘어가기") {go(to:.direction)}.readAloudTarget("넘어가기 버튼").accessibilityIdentifier("tutorial.next")
            } else {
                VStack(spacing:10) {
                    SettingsCapsuleButton(title:"이전으로",primary:false) {if let previous=step.previous {go(to:previous)} else {model.stop()}}
                        .readAloudTarget("이전으로 버튼").accessibilityIdentifier("tutorial.previous")
                    SettingsCapsuleButton(title:step.next == nil ? "목록으로" : "다음으로") {
                        if let next=step.next {go(to:next)} else {model.stop();dismiss()}
                    }.readAloudTarget(step.next == nil ? "목록으로 버튼" : "다음으로 버튼").accessibilityIdentifier("tutorial.next")
                }
            }
        }
        .settingsScreen()
        .navigationTitle(step == .preparation ? "음량 조절" : step.title).navigationBarTitleDisplayMode(.inline)
        .readsAloud(title:step == .preparation ? "음량 조절" : step.title) {model.stop();return readAloudLines}
        .onAppear {
            model.appear()
            let model=model
            volume.onChange = { [weak model] in
                guard let model, step == .preparation else {return}
                let ding=SoundTestSection.preparation.groups.first?.examples.first
                if let ding, model.activeID != ding.id {model.play(ding)}
            }
        }
        .onDisappear {model.disappear();volume.onChange=nil}
        .onChange(of:scenePhase) {_,phase in if phase != .active {model.stop()} }
    }

    /// Figma 457:13574: symbol, 26pt title, 20pt copy, then the 「출발음」 slider.
    private var volumePage: some View {
        VStack(spacing:0) {
            Image(systemName:"speaker.wave.3.fill").font(.system(size:44,weight:.semibold)).foregroundStyle(.white)
                .frame(height:51).padding(.top,150).accessibilityHidden(true)
            Text("소리가 잘 들리시나요?").font(.system(size:26,weight:.bold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
                .readAloudTarget("소리가 잘 들리시나요?").padding(.top,40).accessibilityAddTraits(.isHeader).accessibilityFocused($headingFocused)
            Text("안내음성을 듣기 전\n음량을 조절해주세요").font(.system(size:20,weight:.medium)).foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center).lineSpacing(4).fixedSize(horizontal:false,vertical:true)
                .readAloudTarget("안내음성을 듣기 전 음량을 조절해주세요").padding(.top,16)
            VStack(spacing:0) {
                Text("출발음").font(.system(size:15)).foregroundStyle(SettingsStyle.secondary)
                    .padding(.leading,14).padding(.vertical,8).frame(maxWidth:.infinity,alignment:.leading).accessibilityAddTraits(.isHeader)
                SystemVolumeSlider()
            }.readAloudTarget("출발음 음량 조절").padding(.top,25)
            if let error=model.error {TutorialPlaybackError(message:error).padding(.top,12)}
        }.frame(maxWidth:.infinity)
    }

    /// Figma 457:13690: dots, 26pt title with 18pt copy, the 정면 찾기 card, then 68pt rows under 17pt captions.
    private var lessonPage: some View {
        VStack(alignment:.leading,spacing:0) {
            pageDots.frame(maxWidth:.infinity).padding(.top,16)
            VStack(alignment:.leading,spacing:12) {
                Text(heading).font(.system(size:26,weight:.bold)).foregroundStyle(.white).readAloudTarget(heading)
                    .accessibilityAddTraits(.isHeader).accessibilityFocused($headingFocused)
                Text(explanation).font(.system(size:18)).foregroundStyle(.white.opacity(0.8)).lineSpacing(4)
                    .fixedSize(horizontal:false,vertical:true).readAloudTarget(step.explanation)
            }.padding(.horizontal,14).padding(.top,36)
            if step == .direction {frontPracticeCard.padding(.top,30)}
            if let error=model.error {TutorialPlaybackError(message:error).padding(.top,16)}
            VStack(spacing:16) {
                ForEach(step.groups) { group in
                    VStack(spacing:0) {
                        SettingsSectionHeader(title:group.title,size:17,weight:.semibold)
                        SettingsGroup {
                            ForEach(group.examples) { example in
                                if example.id != group.examples.first?.id {SettingsDivider()}
                                TutorialExampleRow(example:example,model:model)
                            }
                        }
                    }
                }
            }.padding(.top,30)
        }
    }

    private var pageDots: some View {
        HStack(spacing:6) {
            ForEach(lessons) { item in
                Circle().fill(item == step ? Color.white : Color.white.opacity(0.3)).frame(width:6,height:6)
            }
        }.padding(.horizontal,12).frame(height:26).background(SettingsStyle.dimButton,in:Capsule())
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("\(lessons.firstIndex(of:step).map {$0+1} ?? 1) / \(lessons.count) 단계")
    }

    /// 370×226 card with two soft blobs in its corners (Figma 457:13710).
    private var frontPracticeCard: some View {
        NavigationLink {FrontDirectionPracticeView()} label: {
            VStack(spacing:5) {
                Image(systemName:"safari").font(.system(size:46,weight:.regular)).foregroundStyle(.white).frame(width:58,height:58)
                VStack(spacing:3) {
                    Text("정면 찾기").font(.system(size:26,weight:.semibold)).tracking(-0.78).foregroundStyle(.white)
                    Text("방향 구별을 위해 연습을 해보아요").font(.system(size:16)).tracking(-0.48).foregroundStyle(.white.opacity(0.8))
                }.lineLimit(1).minimumScaleFactor(0.8)
            }.padding(.top,41).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top).frame(height:226)
                .background {
                    ZStack {
                        // Figma Ellipse 31 (191pt white disc at 64%, layer blur 75) past the bottom-left and top-right corners.
                        // Drawn as the blurred disc's own falloff, measured from the design's render, instead of SwiftUI's blur,
                        // which spreads the same values into a haze over the whole card.
                        CardCornerGlow().offset(x:-185+95.5-77,y:-113+95.5+112)
                        CardCornerGlow().offset(x:-185+95.5+290,y:-113+95.5-116)
                    }
                }
                .background(Color.white.opacity(0.05),in:RoundedRectangle(cornerRadius:34,style:.continuous))
                .clipShape(RoundedRectangle(cornerRadius:34,style:.continuous))
                .contentShape(RoundedRectangle(cornerRadius:34,style:.continuous))
        }.buttonStyle(.plain).readAloudTarget("정면 찾기","방향 구별을 위해 연습을 해보아요")
            .accessibilityLabel("정면 찾기 연습").accessibilityHint("방향 구별을 위해 몸을 돌려 연습해요")
            .accessibilityIdentifier("tutorial.front-practice")
    }

    /// The page from the top: title, heading, copy, the 정면 찾기 card, then every group and its sounds.
    private var readAloudLines: [String] {
        if step == .preparation {
            return ["음량 조절","소리가 잘 들리시나요?","안내음성을 듣기 전 음량을 조절해주세요","출발음 음량 조절","넘어가기 버튼"]
        }
        var lines=[step.title,heading,step.explanation]
        if step == .direction {lines+=["정면 찾기","방향 구별을 위해 연습을 해보아요"]}
        for group in step.groups {
            lines.append(group.title)
            lines+=group.examples.map {"\($0.title), \($0.detail)"}
        }
        lines+=["이전으로 버튼",step.next == nil ? "목록으로 버튼" : "다음으로 버튼"]
        return lines
    }

    private var heading: String {
        switch step {
        case .preparation: return "소리가 잘 들리시나요?"
        case .direction: return "방향을 알려줘요"
        case .alignment: return "진행 상황 알림"
        case .arrival: return "포인트 확인"
        case .objects: return "장애물 및 기물 확인"
        }
    }
    /// The spoken copy says 「피원」 so speech reads it right; the screen shows P1.
    private var explanation: String {
        step == .arrival ? step.explanation.replacingOccurrences(of:"피원",with:"P1").replacingOccurrences(of:"피투",with:"P2") : step.explanation
    }
}

private struct CardCornerGlow: View {
    /// White alpha by distance from the disc's centre, binned from the design's render every 20pt (0.38 at the centre,
    /// 0.09 at 140pt, 0.013 at 200pt, gone by 240pt).
    private static let profile: [(CGFloat, Double)] = [(0,0.385),(40,0.37),(60,0.32),(80,0.255),(100,0.19),(120,0.133),(140,0.089),(160,0.052),(180,0.03),(200,0.013),(220,0.005),(240,0)]
    private static let stops=profile.map {Gradient.Stop(color:.white.opacity($0.1),location:$0.0/240)}
    var body: some View {
        Circle().fill(RadialGradient(stops:Self.stops,center:.center,startRadius:0,endRadius:240)).frame(width:480,height:480)
    }
}

enum SettingsSymbols {
    /// Figma uses the 「voiceover」 symbol; older systems fall back to a speaker.
    static let readAloud = UIImage(systemName:"voiceover") != nil ? "voiceover" : "speaker.wave.2"
}

/// Notices the hardware volume changing, so the volume page can play the start tone while it is adjusted.
@MainActor final class VolumeWatcher: ObservableObject {
    var onChange: (() -> Void)?
    private var observation: NSKeyValueObservation?
    private var pending: Task<Void, Never>?
    init() {
        observation=AVAudioSession.sharedInstance().observe(\.outputVolume,options:[.new]) {[weak self] _,_ in
            Task { @MainActor in self?.changed() }
        }
    }
    private func changed() {
        pending?.cancel()
        pending=Task { @MainActor [weak self] in
            do {try await Task.sleep(nanoseconds:250_000_000)} catch {return}
            self?.onChange?()
        }
    }
}
