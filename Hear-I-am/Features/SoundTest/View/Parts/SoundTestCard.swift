import SwiftUI
import AVKit
import MediaPlayer
import CoreMotion
import HearIAmCore

// MARK: - Settings look (Figma 「설정」 457:14420 and its children; sizes are the design's)

enum SettingsStyle {
    static let group=Color(red:28/255,green:28/255,blue:30/255)                       // #1C1C1E
    static let secondary=Color(red:235/255,green:235/255,blue:245/255).opacity(0.7)   // labels/secondary
    static let separator=Color(red:84/255,green:84/255,blue:88/255).opacity(0.65)     // separators/dark
    static let darkText=Color(red:38/255,green:38/255,blue:38/255)                    // #262626 on white buttons
    static let dimButton=Color.white.opacity(0.1)
    static let cornerRadius: CGFloat=26
    static let rowHeight: CGFloat=52
    static let tallRowHeight: CGFloat=68
    static let buttonHeight: CGFloat=50
    static let rowInset: CGFloat=18
}

/// A section caption above a rounded group: 13pt on Settings, 15pt on the tutorial list, 17pt semibold on lesson pages.
struct SettingsSectionHeader: View {
    let title: String
    var size: CGFloat=13
    var weight: Font.Weight = .regular
    var body: some View {
        Text(title).font(.system(size:size,weight:weight)).foregroundStyle(SettingsStyle.secondary)
            .lineLimit(1).readAloudTarget(title)
            .padding(.leading,16).padding(.bottom,8).frame(maxWidth:.infinity,alignment:.leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One rounded dark group (#1C1C1E, radius 26). Put `SettingsDivider()` between rows.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing:0) {content}
            .background(SettingsStyle.group,in:RoundedRectangle(cornerRadius:SettingsStyle.cornerRadius,style:.continuous))
            .clipShape(RoundedRectangle(cornerRadius:SettingsStyle.cornerRadius,style:.continuous))
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(SettingsStyle.separator).frame(height:1/UIScreen.main.scale*2)
            .padding(.leading,SettingsStyle.rowInset).accessibilityHidden(true)
    }
}

/// Title, optional detail line, trailing value and an accessory: 52pt single-line rows, 68pt with a detail line.
struct SettingsRowLabel: View {
    enum Accessory { case none, chevron, chevronDown, checkmark, play, stop, externalLink }
    let title: String
    var detail: String?=nil
    var value: String?=nil
    var accessory: Accessory = .chevron
    /// Keep the confirmed tutorial layout; new settings rows can grow for larger text and device names.
    var adaptsToDynamicType=false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing:8) {
            if adaptsToDynamicType && dynamicTypeSize.isAccessibilitySize {
                VStack(alignment:.leading,spacing:6) {titleLabel;valueLabel}
                    .frame(maxWidth:.infinity,alignment:.leading)
            } else {
                titleLabel.frame(maxWidth:.infinity,alignment:.leading)
                valueLabel
            }
            accessoryImage.accessibilityHidden(true)
        }.padding(.horizontal,SettingsStyle.rowInset)
            .padding(.vertical,adaptsToDynamicType ? 12 : 0)
            .frame(maxWidth:.infinity,minHeight:detail == nil ? SettingsStyle.rowHeight : SettingsStyle.tallRowHeight,alignment:.leading)
            .contentShape(Rectangle())
    }
    private var titleLabel: some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(adaptsToDynamicType ? .body : .system(size:17)).foregroundStyle(.white)
                .lineLimit(adaptsToDynamicType ? nil : 1)
                .fixedSize(horizontal:false,vertical:adaptsToDynamicType)
            if let detail {
                Text(detail).font(adaptsToDynamicType ? .subheadline : .system(size:15)).foregroundStyle(SettingsStyle.secondary)
                    .lineLimit(adaptsToDynamicType ? nil : 1)
                    .fixedSize(horizontal:false,vertical:adaptsToDynamicType)
            }
        }
    }
    @ViewBuilder private var valueLabel: some View {
        if let value {
            Text(value).font(adaptsToDynamicType ? .body : .system(size:17)).foregroundStyle(SettingsStyle.secondary)
                .lineLimit(adaptsToDynamicType ? nil : 1)
                .minimumScaleFactor(adaptsToDynamicType ? 1 : 0.8)
                .fixedSize(horizontal:false,vertical:adaptsToDynamicType)
        }
    }
    @ViewBuilder private var accessoryImage: some View {
        switch accessory {
        case .none: EmptyView()
        case .chevron: Image(systemName:"chevron.right").font(.system(size:14,weight:.semibold)).foregroundStyle(SettingsStyle.secondary.opacity(0.5))
        case .chevronDown: Image(systemName:"chevron.down").font(.system(size:14,weight:.medium)).foregroundStyle(SettingsStyle.secondary)
        case .checkmark: Image(systemName:"checkmark").font(.system(size:17,weight:.semibold)).foregroundStyle(.white)
        case .play: Image(systemName:"play.fill").font(.system(size:17)).foregroundStyle(.white)
        case .stop: Image(systemName:"stop.fill").font(.system(size:17)).foregroundStyle(.white)
        case .externalLink: Image(systemName:"arrow.up.right.square").font(.system(size:18)).foregroundStyle(.white)
        }
    }
}

/// The 50pt capsule label: white with dark text, or Liquid Glass tinted 10% white so the page shows through it.
struct SettingsCapsuleLabel: View {
    let title: String
    var primary=true
    var body: some View {
        Text(title).font(.system(size:18,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(primary ? SettingsStyle.darkText : .white)
            .frame(maxWidth:.infinity,minHeight:SettingsStyle.buttonHeight)
            .modifier(CapsuleFill(primary:primary))
            .contentShape(Capsule())
    }
    private struct CapsuleFill: ViewModifier {
        let primary: Bool
        func body(content: Content) -> some View {
            if primary {content.background(Color.white,in:Capsule())}
            else {content.liquidGlass(Capsule(),tint:SettingsStyle.dimButton)}
        }
    }
}

struct SettingsCapsuleButton: View {
    let title: String
    var primary=true
    let action: () -> Void
    var body: some View {
        Button(action:action) {SettingsCapsuleLabel(title:title,primary:primary)}.buttonStyle(.plain)
    }
}

extension View {
    /// Bottom buttons over the design's fade (clear → #00070A, about 150pt), 16pt from the sides. Rows scrolling
    /// underneath stay visible through the fade and the glass button.
    func settingsBottomBar<Bar: View>(inset: CGFloat=16, @ViewBuilder _ bar: () -> Bar) -> some View {
        safeAreaInset(edge:.bottom,spacing:0) {
            let fade=Color(red:0,green:7/255,blue:10/255)
            bar().padding(.horizontal,inset).padding(.top,44).padding(.bottom,10)
                .background(LinearGradient(colors:[fade.opacity(0),fade],startPoint:.top,endPoint:.bottom).ignoresSafeArea())
        }
    }
    func settingsScreen() -> some View {
        background(Color.black.ignoresSafeArea()).toolbar(.hidden,for:.tabBar).tint(.white).preferredColorScheme(.dark)
    }
}

// MARK: - Playing examples

struct TutorialExampleRow: View {
    let example: SignalTutorialExample
    @ObservedObject var model: SoundTestViewModel
    private var playing: Bool {model.activeID == example.id}
    var body: some View {
        Button {model.play(example)} label: {
            SettingsRowLabel(title:example.title,detail:playing ? L("재생 중 · 누르면 중지") : example.detail,accessory:playing ? .stop : .play)
        }.buttonStyle(.plain).readAloudTarget("\(example.title), \(example.detail)")
            .accessibilityLabel(example.title+(playing ? L(" 중지") : L(" 듣기")))
            .accessibilityValue(playing ? L("재생 중") : "")
            .accessibilityHint(example.detail)
            .accessibilityIdentifier("tutorial.preview."+example.id)
    }
}

struct TutorialPlaybackError: View {
    let message: String
    var body: some View {
        Label(message,systemImage:"exclamationmark.circle").font(.system(size:15)).foregroundStyle(.white)
            .fixedSize(horizontal:false,vertical:true).padding(14).frame(maxWidth:.infinity,alignment:.leading)
            .background(SettingsStyle.group,in:RoundedRectangle(cornerRadius:18,style:.continuous))
    }
}

// MARK: - Output device

/// 「출력 기기」 row. Tapping opens the system route picker, the only public way to switch AirPods or speakers.
struct OutputDeviceRow: View {
    @ObservedObject var output: SoundOutputStatus
    @State private var picker=RoutePicker()
    var body: some View {
        Button {picker.present()} label: {
            SettingsRowLabel(title:L("출력 기기"),value:output.name,accessory:.chevronDown,adaptsToDynamicType:true)
        }.buttonStyle(.plain)
            // The system picker draws its AirPlay glyph past a 1pt frame, so it is clipped away; the row stays the only visible control.
            .background(RoutePickerHost(picker:picker).frame(width:1,height:1).clipped().opacity(0.01).accessibilityHidden(true))
            .background(SettingsStyle.group,in:RoundedRectangle(cornerRadius:SettingsStyle.cornerRadius,style:.continuous))
            .accessibilityLabel(L("출력 기기, %@", output.name)).accessibilityHint(L("눌러서 소리가 나올 기기를 바꿔요"))
            .accessibilityIdentifier("output.device")
    }
}

final class RoutePicker {
    let view: AVRoutePickerView = {
        let view=AVRoutePickerView()
        view.prioritizesVideoDevices=false
        return view
    }()
    func present() {
        (view.subviews.compactMap {$0 as? UIButton}.first)?.sendActions(for:.touchUpInside)
    }
}

private struct RoutePickerHost: UIViewRepresentable {
    let picker: RoutePicker
    func makeUIView(context: Context) -> AVRoutePickerView {picker.view}
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

/// The system volume as a 52pt slider row (Figma 「음량 조절 / iOS Slider」).
struct SystemVolumeSlider: View {
    var body: some View {
        HStack(spacing:14) {
            Image(systemName:"speaker.wave.1.fill").font(.system(size:15)).foregroundStyle(SettingsStyle.secondary).accessibilityHidden(true)
            VolumeViewHost().frame(height:34)
            Image(systemName:"speaker.wave.3.fill").font(.system(size:15)).foregroundStyle(SettingsStyle.secondary).accessibilityHidden(true)
        }.padding(.horizontal,SettingsStyle.rowInset).frame(height:SettingsStyle.rowHeight)
            .background(SettingsStyle.group,in:RoundedRectangle(cornerRadius:SettingsStyle.cornerRadius,style:.continuous))
    }
}

private struct VolumeViewHost: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view=CenteredVolumeView(frame:.zero)
        view.tintColor = .white
        return view
    }
    func updateUIView(_ view: MPVolumeView, context: Context) {}
}

/// MPVolumeView lays its slider toward the top of its bounds; the design wants it on the row's centre line.
private final class CenteredVolumeView: MPVolumeView {
    override func volumeSliderRect(forBounds bounds: CGRect) -> CGRect {
        let slider=super.volumeSliderRect(forBounds:bounds)
        return CGRect(x:bounds.minX,y:bounds.midY-slider.height/2,width:bounds.width,height:slider.height)
    }
}

// MARK: - Read aloud

/// The toolbar's 「voiceover」 button on every settings page (Figma 457:15618 and the others): it reads the page
/// from the top, one line after another, and turns into a stop button while it speaks.
@MainActor final class PageReader: ObservableObject {
    static let shared=PageReader()
    @Published private(set) var reading=false
    @Published private(set) var error: String?
    /// The line being spoken, so the page can box the part it belongs to (see readAloudTarget).
    @Published private(set) var currentLine: String?
    private let speech=GuidanceSpeech()
    private init() {
        speech.onSpeaking={[weak self] on in self?.reading=on; if !on {self?.currentLine=nil}}
        speech.onText={[weak self] text in self?.currentLine=text.trimmingCharacters(in:.whitespacesAndNewlines)}
        speech.onError={[weak self] message in self?.error=message}
    }
    func toggle(_ lines: [String]) {if reading {stop()} else {read(lines)}}
    func read(_ lines: [String]) {
        let cleaned=lines.map {$0.trimmingCharacters(in:.whitespacesAndNewlines)}.filter {!$0.isEmpty}
        guard !cleaned.isEmpty else {return}
        error=nil
        speech.play(cleaned)
    }
    func stop() {speech.stop()}
}

struct ReadAloudButton: View {
    let lines: () -> [String]
    @ObservedObject private var reader=PageReader.shared
    var body: some View {
        Button {reader.toggle(lines())} label: {ScanCircleLabel(systemImage:reader.reading ? "stop.fill" : SettingsSymbols.readAloud)}
            .buttonStyle(.plain).animation(nil,value:reader.reading)
            .accessibilityLabel(reader.reading ? L("읽기 중지") : L("화면 읽어주기")).accessibilityIdentifier("settings.readAloud")
    }
}

extension View {
    /// The settings pages' top row (HearTopBar: back, title, read-aloud) in place of the navigation bar; reading stops when
    /// the page goes away. `lines` runs when the button is tapped, so it can stop other playback first.
    func readsAloud(title: String, _ lines: @escaping () -> [String]) -> some View {
        modifier(SettingsHeaderModifier(title:title,lines:lines))
    }
}

private struct SettingsHeaderModifier: ViewModifier {
    let title: String
    let lines: () -> [String]
    @Environment(\.dismiss) private var dismiss
    func body(content: Content) -> some View {
        content.hearTopBar(title) {HearBackButton()} trailing: {ReadAloudButton(lines:lines)}
            .overlayPreferenceValue(ReadAloudTargets.self) {targets in ReadAloudHighlight(targets:targets)}
            #if DEBUG
            // Screenshots of the reading box: `--read-aloud-autostart` reads the page as soon as it shows.
            .task {
                guard ProcessInfo.processInfo.arguments.contains("--read-aloud-autostart") else {return}
                try? await Task.sleep(for:.seconds(1));PageReader.shared.read(lines())
            }
            #endif
            // VoiceOver's two-finger scrub still goes back without the system bar.
            .accessibilityAction(.escape) {dismiss()}
            .onDisappear {PageReader.shared.stop()}
    }
}

/// The connected device drawn at the design's 150pt and tilting with the phone, so it reads as an object
/// (Figma 457:13480 · 13846 · 13950). It springs in again whenever the device changes.
struct OutputDeviceHero: View {
    @ObservedObject var output: SoundOutputStatus
    @StateObject private var tilt=DeviceTilt()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared=false
    var body: some View {
        VStack(spacing:5) {
            Group {
                switch output.kind {
                case .iPhone: device("DeviceIPhone",size:150)
                case .airPodsMax: device("DeviceAirPodsMax",size:160)
                // Earphones and headsets other than AirPods use the design's headphone picture (971:35244).
                case .headphones: device("DeviceAirPodsMax",size:160)
                case .externalAudio: genericDevice("speaker.wave.2")
                case .airPods:
                    HStack(spacing:18) {device("DeviceAirPods",size:140);device("DeviceAirPodsCase",size:120)}
                }
            }.frame(height:162).scaleEffect(appeared ? 1 : 0.86).opacity(appeared ? 1 : 0)
                .readAloudTarget(L("연결된 기기, %@", output.name))
            Text(output.name).font(.body.weight(.semibold)).foregroundStyle(.white)
                .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
        }.padding(.top,32).padding(.bottom,24)
            .frame(maxWidth:.infinity,minHeight:275,alignment:.top)
            .accessibilityElement(children:.ignore).accessibilityLabel(L("출력 기기, %@", output.name))
            .accessibilityIdentifier("output.deviceHero")
            .onAppear {
                if !reduceMotion {tilt.start()}
                revealDevice()
            }
            .onDisappear {tilt.stop();appeared=false}
            .onChange(of:output.kind) {_,_ in revealDevice()}
            .onChange(of:reduceMotion) {_,reduced in
                if reduced {tilt.stop()} else {tilt.start()}
            }
    }
    private func revealDevice() {
        if reduceMotion {appeared=true}
        else {
            appeared=false
            withAnimation(.spring(response:0.6,dampingFraction:0.75)) {appeared=true}
        }
    }
    private func genericDevice(_ symbol: String) -> some View {
        Image(systemName:symbol).font(.system(size:88,weight:.light)).foregroundStyle(.white)
            .frame(width:160,height:160).accessibilityHidden(true)
    }
    private func device(_ name: String, size: CGFloat) -> some View {
        Image(name).resizable().scaledToFit().frame(width:size,height:size)
            .modifier(TiltEffect(tilt:tilt,enabled:!reduceMotion))
    }
}

/// Small rotations from the phone's attitude, smoothed so the image sways instead of jittering.
@MainActor final class DeviceTilt: ObservableObject {
    @Published private(set) var pitch=0.0
    @Published private(set) var roll=0.0
    private let motion=CMMotionManager()
    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else {return}
        motion.deviceMotionUpdateInterval=1.0/30.0
        motion.startDeviceMotionUpdates(to:.main) {[weak self] sample,_ in
            guard let self, let gravity=sample?.gravity else {return}
            // Held in the hand, gravity.z sits near -0.6; tipping the phone moves z and x.
            let targetPitch=max(-1,min(1,(gravity.z+0.6)*1.6))*12
            let targetRoll=max(-1,min(1,gravity.x*1.6))*16
            self.pitch+=(targetPitch-self.pitch)*0.12
            self.roll+=(targetRoll-self.roll)*0.12
        }
    }
    func stop() {motion.stopDeviceMotionUpdates();pitch=0;roll=0}
}

private struct TiltEffect: ViewModifier {
    @ObservedObject var tilt: DeviceTilt
    let enabled: Bool
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(enabled ? tilt.roll : 0),axis:(x:0,y:1,z:0),perspective:0.5)
            .rotation3DEffect(.degrees(enabled ? -tilt.pitch : 0),axis:(x:1,y:0,z:0),perspective:0.5)
            .shadow(color:.white.opacity(0.08),radius:24,x:enabled ? -tilt.roll : 0,y:12)
    }
}

// MARK: - Showing what is being read

/// Where each read-aloud line sits on the page, keyed by the line's text.
struct ReadAloudTargets: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>]=[:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) {first,_ in first}
    }
}

extension View {
    /// Marks this view as the part of the page that the given read-aloud lines describe, so the blue box
    /// lands on it while one of them is spoken (Figma 971:16696 · 16790 · 16884). Lines must match the page's
    /// `readsAloud` lines word for word.
    func readAloudTarget(_ lines: String...) -> some View {
        anchorPreference(key:ReadAloudTargets.self,value:.bounds) {anchor in
            Dictionary(lines.map {($0.trimmingCharacters(in:.whitespacesAndNewlines),anchor)}) {first,_ in first}
        }
    }
    func readAloudTarget(_ lines: [String]) -> some View {
        anchorPreference(key:ReadAloudTargets.self,value:.bounds) {anchor in
            Dictionary(lines.map {($0.trimmingCharacters(in:.whitespacesAndNewlines),anchor)}) {first,_ in first}
        }
    }
}

/// The 2.5pt blue box around the part being read, moving from part to part with the voice, like the
/// VoiceOver cursor (971:16696). Lines with no marked part show no box.
private struct ReadAloudHighlight: View {
    let targets: [String: Anchor<CGRect>]
    @ObservedObject private var reader=PageReader.shared
    static let blue=Color(red:0,green:136/255,blue:1)   // #0088FF
    var body: some View {
        GeometryReader {proxy in
            if reader.reading, let line=reader.currentLine, let anchor=targets[line] {
                let rect=proxy[anchor].insetBy(dx:-4,dy:-4)
                Rectangle().strokeBorder(Self.blue,lineWidth:2.5)
                    .frame(width:rect.width,height:rect.height).position(x:rect.midX,y:rect.midY)
                    .animation(.snappy(duration:0.25),value:line)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
