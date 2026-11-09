import SwiftUI
import UIKit
import HearIAmCore

/// The performer's voice screens, Figma 「apple intellenge」 (495:5074–5569): a dark canvas with the three
/// lights below, the performer's requests as bubbles on the right, the app's answers as plain lines on the
/// left and the performances it found as cards.
enum VoiceStyle {
    static let canvas=Color(red:0,green:7/255,blue:10/255)
    static let bubble=Color.white.opacity(0.1)
    static let meta=Color(red:118/255,green:118/255,blue:118/255)
    static let status=Color(red:153/255,green:153/255,blue:153/255)
    static let arrow=Color(red:245/255,green:245/255,blue:245/255)
    private static let clock: DateFormatter = {
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"ko_KR");formatter.dateFormat="a h:mm";return formatter
    }()
    static func time(_ date: Date) -> String {clock.string(from:date)}
}

/// The three blurred radial lights under the conversation (495:5091: cobalt, violet, teal). They sit mostly
/// below the screen so only their upper halves show. They breathe: each swells and dims on its own slow
/// cycle while drifting sideways, so the three colours keep flowing into one another (11/02).
struct VoiceBloom: View {
    var animating=true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private struct Light {let color: Color; let alpha: Double; let x: CGFloat; let y: CGFloat; let rx: CGFloat; let ry: CGFloat}
    /// Centres and radii as fractions of the 402×874 design frame.
    private static let lights=[
        Light(color:Color(red:0x3D/255,green:0x72/255,blue:0xBB/255),alpha:0.66,x:0.498,y:1.013,rx:0.647,ry:0.262),
        Light(color:Color(red:0x67/255,green:0x54/255,blue:0x9C/255),alpha:0.51,x:0.050,y:1.022,rx:0.510,ry:0.228),
        Light(color:Color(red:0x3B/255,green:0x84/255,blue:0x91/255),alpha:0.55,x:1.065,y:1.016,rx:0.522,ry:0.240)]

    var body: some View {
        TimelineView(.animation(minimumInterval:1.0/30,paused:!animating || reduceMotion)) {timeline in
            let time=reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            GeometryReader {geometry in
                let w=geometry.size.width, h=geometry.size.height
                ZStack {
                    ForEach(Array(Self.lights.enumerated()),id:\.offset) {index,light in
                        let phase=Double(index)*2.1
                        // Restless on purpose (11/03 「좀 더 요동치게」): a wide sway with a quicker wobble on top, a breath
                        // of up to ±35%, a surge of up to 110pt and a flicker, on 3–5 s periods with 1–2 s ripples.
                        let drift=sin(time*1.35+phase)*0.24+sin(time*3.1+phase*2.3)*0.06
                        let breath=1+0.27*sin(time*1.7+phase*1.7)+0.08*sin(time*4.3+phase)
                        let lift=(1-cos(time*1.2+phase))*45+abs(sin(time*2.6+phase*1.3))*20
                        let glow=0.6+0.3*sin(time*2.1+phase*0.6)+0.1*sin(time*5.2+phase)
                        let radius=light.rx*w
                        Circle().fill(RadialGradient(stops:[
                            .init(color:light.color.opacity(light.alpha),location:0),
                            .init(color:light.color.opacity(light.alpha*0.82),location:0.3),
                            .init(color:light.color.opacity(light.alpha*0.3),location:0.68),
                            .init(color:light.color.opacity(0),location:1)],center:.center,startRadius:0,endRadius:radius))
                        .frame(width:radius*2,height:radius*2)
                        .scaleEffect(x:breath,y:light.ry*h/radius*breath)
                        .opacity(glow)
                        .position(x:(light.x+drift)*w,y:light.y*h-lift)
                    }
                }.blur(radius:15)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// The stroke logo running through its 4 s loop, the design's 「Stroke Logo · OPPOSITE PAIRS」 (495:5103)
/// next to what the app is doing, and the large one on the empty screen (495:5077).
struct VoiceLogoSpinner: View {
    var size: CGFloat
    var animating=true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval:1.0/30,paused:!animating || reduceMotion)) {timeline in
            let time=reduceMotion ? StrokeLogoShape.settled : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:StrokeLogoShape.loop)
            HearStrokeLogo(size:size,time:time)
        }.frame(width:size,height:size)
    }
}

/// The empty conversation (495:5074), and the performer's first screen before the call (971:36998): the logo
/// over the question, with a grey line under it, 「HearIam을 불러주세요」 before the call. The group's middle is
/// 30pt above the screen's.
struct VoiceWaitingPrompt: View {
    var text="오늘은 어떤 공연을\n연습할까요?"
    var subtitle: String?=nil
    var animating=true
    var body: some View {
        VStack(spacing:36) {
            VoiceLogoSpinner(size:74,animating:animating).opacity(0.5)
            VStack(spacing:12) {
                Text(text).font(HearFont.pretendard(.semibold,size:32)).tracking(-0.96).lineSpacing(4)
                    .foregroundStyle(.white).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                if let subtitle {
                    Text(subtitle).font(HearFont.pretendard(.medium,size:24)).tracking(-0.72)
                        .foregroundStyle(VoiceStyle.meta).multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                }
            }
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity).offset(y:-30)
        .accessibilityElement(children:.combine)
    }
}

/// The chevron the design uses instead of a navigation bar (iOS 「Accessory Bar」). It sits in the toolbar,
/// which draws the glass circle itself on iOS 26; drawing another one underneath doubled the button.
struct VoiceBackButton: View {
    let action: () -> Void
    var body: some View {
        Button(action:action) {
            Image(systemName:"chevron.left").font(.system(size:17,weight:.semibold)).foregroundStyle(.white)
        }
        .accessibilityLabel("뒤로")
    }
}

/// Time of the line with copy and, for the performer's own words, edit (495:5123).
struct VoiceChatMeta: View {
    let date: Date
    let text: String
    var onEdit: (() -> Void)? = nil
    var body: some View {
        HStack(spacing:10) {
            Text(VoiceStyle.time(date))
            Button {UIPasteboard.general.string=text} label: {Image(systemName:"doc.on.doc").frame(width:24,height:24)}
                .accessibilityLabel("복사")
            if let onEdit {
                Button(action:onEdit) {Image(systemName:"pencil").frame(width:24,height:24).padding(6).contentShape(Rectangle())}
                    .padding(-6).accessibilityLabel("수정")
            }
        }
        .font(.system(size:14)).foregroundStyle(VoiceStyle.meta).buttonStyle(.plain)
    }
}

/// What the performer said, on the right (495:5120). The pencil opens the words for correction and sends them again.
struct VoiceUserBubble: View {
    let text: String
    let date: Date
    var resend: ((String) -> Void)? = nil
    var beginEdit: (() -> Void)? = nil
    /// Off for the words still being spoken: they have no time, copy or edit yet.
    var showsMeta=true
    /// Words arriving while they are said appear letter by letter, as dictation types them (11/03).
    var typing=false
    @State private var editing=false
    @State private var draft=""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment:.trailing,spacing:8) {
            Group {
                if editing {
                    HStack(alignment:.bottom,spacing:8) {
                        TextField("요청",text:$draft,axis:.vertical).focused($focused).lineLimit(1...4)
                            .font(.system(size:16,weight:.medium)).foregroundStyle(.white)
                            .submitLabel(.send).onSubmit(send)
                        Button(action:send) {Image(systemName:"arrow.up.circle.fill").font(.system(size:24))}
                            .buttonStyle(.plain).foregroundStyle(.white).accessibilityLabel("다시 보내기")
                    }
                } else if typing {
                    VoiceTypingText(text:text).font(.system(size:16,weight:.medium)).lineSpacing(3).foregroundStyle(.white)
                        .fixedSize(horizontal:false,vertical:true)
                } else {
                    Text(text).font(.system(size:16,weight:.medium)).lineSpacing(3).foregroundStyle(.white)
                        .fixedSize(horizontal:false,vertical:true)
                }
            }
            .padding(.horizontal,17).padding(.vertical,13)
            .background(VoiceStyle.bubble,in:RoundedRectangle(cornerRadius:24,style:.continuous))
            .frame(maxWidth:274,alignment:.trailing)
            if showsMeta {VoiceChatMeta(date:date,text:text,onEdit:resend == nil ? nil : startEditing).padding(.horizontal,19)}
        }
        .frame(maxWidth:.infinity,alignment:.trailing)
    }
    /// The field exists only after this update, so the keyboard is asked for on the next one; asking in the
    /// same update left the bubble unfocused and nothing could be typed (11/03).
    private func startEditing() {
        draft=text;editing=true
        beginEdit?()
        DispatchQueue.main.async {focused=true}
    }
    private func send() {
        editing=false;focused=false
        let request=draft.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !request.isEmpty else {return}
        resend?(request)
    }
}

/// Text that catches up with what has been heard a letter at a time, so the words seem typed as spoken.
/// A recognizer revision keeps the letters both versions share and types the rest.
struct VoiceTypingText: View {
    let text: String
    @State private var shown=""
    var body: some View {
        Text(shown.isEmpty ? " " : shown)
            .task(id:text) {
                let target=Array(text)
                var current=Array(shown)
                let common=zip(current,target).prefix {$0 == $1}.count
                current=Array(current.prefix(common))
                shown=String(current)
                while current.count < target.count {
                    try? await Task.sleep(nanoseconds:22_000_000)
                    if Task.isCancelled {return}
                    current.append(target[current.count])
                    shown=String(current)
                }
            }
            .accessibilityLabel(text)
    }
}

/// What the app answered, as plain text on the left (495:5477).
struct VoiceAppLine: View {
    let text: String
    let date: Date
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Text(text).font(.system(size:16,weight:.medium)).lineSpacing(3).foregroundStyle(.white)
                .fixedSize(horizontal:false,vertical:true)
            VoiceChatMeta(date:date,text:text)
        }
        .frame(maxWidth:.infinity,alignment:.leading)
    }
}

/// The performances found: a line of text, then one card per performance with a small plan of its route,
/// the name and its place tags (495:5160). A tap chooses the card like saying its number.
struct VoiceStageCards: View {
    let text: String
    let stages: [VoiceChatStage]
    let date: Date
    let select: (VoiceChatStage) -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Text(text).font(.system(size:16,weight:.medium)).lineSpacing(3).foregroundStyle(.white)
                .fixedSize(horizontal:false,vertical:true).padding(.bottom,16)
            ForEach(stages) {stage in
                Button {select(stage)} label: {
                    HStack(spacing:24) {
                        ZStack {
                            RoundedRectangle(cornerRadius:12.93,style:.continuous).fill(VoiceStyle.bubble)
                            ScanStageMap(style:.editing,showsLabel:false,width:stage.width,depth:stage.depth,points:stage.points,
                                         objects:stage.objects,cornerStates:[true,true,true,true],dimCorners:true)
                                .padding(.horizontal,12).padding(.vertical,10)
                        }
                        .frame(width:118.5,height:87.26)
                        VStack(alignment:.leading,spacing:4) {
                            Text(stage.name).font(.system(size:16,weight:.semibold)).foregroundStyle(.white).lineLimit(1)
                            HStack(spacing:4) {
                                ForEach(stage.tags,id:\.self) {tag in
                                    Text(tag).font(.system(size:13,weight:.medium)).foregroundStyle(.white).lineLimit(1)
                                        .padding(.horizontal,6).padding(.vertical,2).background(VoiceStyle.bubble,in:Capsule())
                                }
                            }
                        }
                        Spacer(minLength:0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(stage.number)번, \(stage.name)\(stage.tags.isEmpty ? "" : ", "+stage.tags.joined(separator:", "))")
                .accessibilityIdentifier("voice.card.\(stage.id)")
            }
            VoiceChatMeta(date:date,text:text+"\n"+stages.map {"\($0.number). \($0.name)"}.joined(separator:"\n"))
        }
        .frame(maxWidth:.infinity,alignment:.leading)
    }
}

/// The spinner line while the app works (495:5102).
struct VoiceStatusRow: View {
    /// What the app is doing; without it only the moving logo shows, waiting for the answer.
    let text: String?
    /// Listening has stopped until the call: the logo stands still.
    var idle=false
    var body: some View {
        HStack(spacing:4) {
            VoiceLogoSpinner(size:35.5,animating:!idle).opacity(0.4).frame(width:50,height:45)
            if let text {Text(text).font(.system(size:16,weight:.medium)).foregroundStyle(VoiceStyle.status)}
        }
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(text ?? "답변을 기다리고 있어요")
        .accessibilityIdentifier("voice.status")
    }
}

/// The conversation from the call to the start of walking guidance: 공연 찾기, 사용 방식 and the 연습용
/// preparation (finding the saved stage, wearing the phone, 「출발」) all happen here as lines of the chat.
/// The camera keeps tracking behind the canvas; nothing of it is shown.
struct VoiceConversationView: View {
    @ObservedObject var library: StageLibrary
    @ObservedObject var model: GuidanceViewModel
    /// The last line the logo stopped waiting under: words that get no answer (noise read as speech) must
    /// not leave it spinning for good.
    @State private var unanswered: VoiceChatEntry.ID?
    /// The newest line is out of view because the performer scrolled up to read back (#158).
    @State private var scrolledUp=false
    @State private var showsJump=false
    var body: some View {
        ZStack(alignment:.top) {
            VoiceStyle.canvas.ignoresSafeArea()
            VoiceBloom(animating:model.active && !model.isSettingsPresented).ignoresSafeArea()
            if model.voiceChat.isEmpty {
                VoiceWaitingPrompt(animating:model.active)
            } else {
                ScrollViewReader {proxy in
                    ScrollView {
                        // A plain stack: the lazy one guessed the height of rows off screen, so scrolling to the
                        // end stopped half way down until the screen was touched (11/02 device test).
                        VStack(alignment:.leading,spacing:24) {
                            ForEach(model.voiceChat) {entry in row(entry).id(entry.id)}
                            // Like a messenger's typing dots: the moving logo sits under the last line while the app
                            // works or has yet to answer the performer's words (11/03).
                            if liveText {
                                VoiceUserBubble(text:model.voiceLiveText,date:Date(),showsMeta:false,typing:true)
                                    .accessibilityLabel("말하는 중: \(model.voiceLiveText)")
                            }
                            else if let status=model.voiceChatStatus {
                                VoiceStatusRow(text:status,idle:status == GuidanceViewModel.voiceAsleepStatus)
                            }
                            else if awaitingAnswer || library.loading {VoiceStatusRow(text:nil)}
                            if model.phase == .selection, model.voiceChoosingMode,
                               model.voiceSelectionControlsVisible || model.voiceInputError != nil || model.audioIssue != nil {
                                modeChoices
                            }
                            Color.clear.frame(height:1).id("end")
                        }
                        .padding(.horizontal,16).padding(.top,32).padding(.bottom,48)
                    }
                    .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
                    .modifier(VoiceScrolledUp(scrolledUp:$scrolledUp))
                    // As in chat apps, a small button under the lines goes back to the newest one. It waits a
                    // moment so a new line growing the list before the automatic scroll does not flash it.
                    .task(id:scrolledUp) {
                        if scrolledUp {try? await Task.sleep(for:.seconds(0.4))}
                        if !Task.isCancelled {withAnimation(.easeOut(duration:0.2)) {showsJump=scrolledUp}}
                    }
                    .overlay(alignment:.bottom) {
                        if showsJump {
                            Button {
                                withAnimation(.easeOut(duration:0.3)) {proxy.scrollTo("end",anchor:.bottom)}
                            } label: {
                                Image(systemName:"arrow.down").font(.system(size:15,weight:.semibold)).foregroundStyle(.white)
                                    .frame(width:36,height:36).liquidGlass(Circle(),interactive:true)
                                    .frame(width:44,height:44).contentShape(Circle())
                            }
                            .buttonStyle(.plain).padding(.bottom,8)
                            .transition(.opacity.combined(with:.scale(scale:0.8)))
                            .accessibilityLabel("맨 아래로 이동")
                        }
                    }
                    .task(id:model.voiceChat.last?.id) {
                        let id=model.voiceChat.last?.id
                        try? await Task.sleep(for:.seconds(12))
                        if !Task.isCancelled {unanswered=id}
                    }
                    // The conversation starts at the top and grows downward; only once it is longer than the
                    // screen does it scroll to keep the newest line in view. One scroll per change, after the
                    // new rows are laid out: a new line and the spinner changing together used to start two
                    // scrolls that stopped each other half way.
                    .onChange(of:scrollKey) {
                        DispatchQueue.main.async {withAnimation(.easeOut(duration:0.25)) {scroll(proxy)}}
                    }
                    .onAppear {DispatchQueue.main.async {proxy.scrollTo("end",anchor:.bottom)}}
                }
            }
            // The lines slide under a fade from the canvas colour at the top (495:5478).
            LinearGradient(stops:[.init(color:VoiceStyle.canvas,location:0.036),.init(color:VoiceStyle.canvas.opacity(0),location:0.596)],
                           startPoint:.top,endPoint:.bottom)
                .frame(height:156).ignoresSafeArea(edges:.top).allowsHitTesting(false).accessibilityHidden(true)
        }
    }
    /// New cards are shown from their top, under the words that asked for them; a long list scrolled to its
    /// end hid the first performances (11/03). Anything else keeps the newest line in view.
    private func scroll(_ proxy: ScrollViewProxy) {
        let chat=model.voiceChat
        if let last=chat.last, case .stages=last.kind {
            proxy.scrollTo(chat.count > 1 ? chat[chat.count-2].id : last.id,anchor:.top)
        } else {
            proxy.scrollTo("end",anchor:.bottom)
        }
    }
    /// Changes whenever a line or the spinner line under the conversation changes.
    private var scrollKey: String {"\(model.voiceChat.count)|\(model.voiceChatStatus ?? "")|\(awaitingAnswer)|\(liveText ? model.voiceLiveText : "")"}
    /// The performer is speaking and some words have come through.
    private var liveText: Bool {model.voiceTurnActive && !model.voiceLiveText.isEmpty}
    /// The performer spoke last and nothing has answered yet.
    private var awaitingAnswer: Bool {
        guard let last=model.voiceChat.last, last.id != unanswered, case .user=last.kind else {return false}
        return true
    }
    @ViewBuilder private func row(_ entry: VoiceChatEntry) -> some View {
        switch entry.kind {
        case .user(let text):
            VoiceUserBubble(text:text,date:entry.date,resend:{model.submitTypedRequest($0,replacing:entry.id)},beginEdit:{model.beginVoiceEdit()})
        case .app(let text): VoiceAppLine(text:text,date:entry.date)
        case .stages(let text,let stages): VoiceStageCards(text:text,stages:stages,date:entry.date) {select($0)}
        }
    }
    /// A card is a performance or one of its stages; the model's own guards decide whether it can still be chosen.
    private func select(_ stage: VoiceChatStage) {
        if let item=model.voiceStages.first(where:{$0.id == stage.id}) {model.select(item)}
        else {model.selectVoicePerformance(stage.id)}
    }
    /// Touch stands in for 「연습용」·「실전용」 when the microphone cannot be used.
    private var modeChoices: some View {
        HStack(spacing:8) {
            ForEach(VoiceUsageMode.allCases) {mode in
                Button(mode.title) {model.selectVoiceMode(mode)}
                    .font(.system(size:16,weight:.semibold)).foregroundStyle(.white)
                    .padding(.horizontal,20).padding(.vertical,12).background(VoiceStyle.bubble,in:Capsule())
                    .accessibilityIdentifier("voice.mode.\(mode.rawValue)")
            }
        }
        .buttonStyle(.plain)
    }
}

/// Whether the end of the conversation is more than a line's height below the screen. Before iOS 18 the
/// position is not reported and the button never shows.
private struct VoiceScrolledUp: ViewModifier {
    @Binding var scrolledUp: Bool
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for:Bool.self) {geometry in
                geometry.contentSize.height + geometry.contentInsets.bottom - geometry.visibleRect.maxY > 120
            } action: {_,up in if scrolledUp != up {scrolledUp=up}}
        } else {content}
    }
}
