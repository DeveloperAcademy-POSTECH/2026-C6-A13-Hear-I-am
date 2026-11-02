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
                        // Sideways drift of up to 7% of the width, a breath of ±12% in size and a rise of up to 28pt,
                        // each on a different period so the pattern never repeats exactly.
                        let drift=sin(time*0.17+phase)*0.07
                        let breath=1+0.12*sin(time*0.31+phase*1.7)
                        let lift=(1-cos(time*0.23+phase))*14
                        let glow=0.82+0.18*sin(time*0.27+phase*0.6)
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

/// The empty conversation after the call (495:5074): the logo over the question.
struct VoiceWaitingPrompt: View {
    var text="오늘은 어떤 공연을\n연습할까요?"
    var animating=true
    var body: some View {
        VStack(spacing:36) {
            VoiceLogoSpinner(size:74,animating:animating).opacity(0.5)
            Text(text).font(.system(size:32,weight:.semibold)).tracking(-0.96).lineSpacing(4)
                .foregroundStyle(.white).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
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
                Button(action:onEdit) {Image(systemName:"pencil").frame(width:24,height:24)}.accessibilityLabel("수정")
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
                } else {
                    Text(text).font(.system(size:16,weight:.medium)).lineSpacing(3).foregroundStyle(.white)
                        .fixedSize(horizontal:false,vertical:true)
                }
            }
            .padding(.horizontal,17).padding(.vertical,13)
            .background(VoiceStyle.bubble,in:RoundedRectangle(cornerRadius:24,style:.continuous))
            .frame(maxWidth:274,alignment:.trailing)
            VoiceChatMeta(date:date,text:text,onEdit:resend == nil ? nil : {draft=text;editing=true;focused=true}).padding(.horizontal,19)
        }
        .frame(maxWidth:.infinity,alignment:.trailing)
    }
    private func send() {
        editing=false;focused=false
        let request=draft.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !request.isEmpty, request != text else {return}
        resend?(request)
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
    let text: String
    var body: some View {
        HStack(spacing:4) {
            VoiceLogoSpinner(size:35.5).opacity(0.4).frame(width:50,height:45)
            Text(text).font(.system(size:16,weight:.medium)).foregroundStyle(VoiceStyle.status)
        }
        .accessibilityElement(children:.combine)
        .accessibilityIdentifier("voice.status")
    }
}

/// The conversation from the call to the start of walking guidance: 공연 찾기, 사용 방식 and the 연습용
/// preparation (finding the saved stage, wearing the phone, 「출발」) all happen here as lines of the chat.
/// The camera keeps tracking behind the canvas; nothing of it is shown.
struct VoiceConversationView: View {
    @ObservedObject var library: StageLibrary
    @ObservedObject var model: GuidanceViewModel
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
                            ForEach(model.voiceChat) {entry in row(entry)}
                            if let status=model.voiceChatStatus {VoiceStatusRow(text:status)}
                            if model.phase == .selection, model.voiceChoosingMode,
                               model.voiceSelectionControlsVisible || model.voiceInputError != nil || model.audioIssue != nil {
                                modeChoices
                            }
                            if library.loading {ProgressView().tint(.white)}
                            Color.clear.frame(height:1).id("end")
                        }
                        .padding(.horizontal,16).padding(.top,32).padding(.bottom,48)
                    }
                    .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
                    // The conversation starts at the top and grows downward; only once it is longer than the
                    // screen does it scroll to keep the newest line in view. One scroll per change, after the
                    // new rows are laid out: a new line and the spinner changing together used to start two
                    // scrolls that stopped each other half way.
                    .onChange(of:scrollKey) {
                        DispatchQueue.main.async {withAnimation(.easeOut(duration:0.25)) {proxy.scrollTo("end",anchor:.bottom)}}
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
    /// Changes whenever a line or the spinner line under the conversation changes.
    private var scrollKey: String {"\(model.voiceChat.count)|\(model.voiceChatStatus ?? "")"}
    @ViewBuilder private func row(_ entry: VoiceChatEntry) -> some View {
        switch entry.kind {
        case .user(let text): VoiceUserBubble(text:text,date:entry.date) {model.submitTypedRequest($0)}
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
