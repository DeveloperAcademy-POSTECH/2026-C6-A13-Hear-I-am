import SwiftUI
import HearIAmCore

/// Settings and its children share Home's navigation stack.
struct HomeSettingsView: View {
    @StateObject private var output=SoundOutputStatus()
    @Environment(\.scenePhase) private var scenePhase
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? L("확인할 수 없음")
    }
    var body: some View {
        ScrollView {
            VStack(spacing:0) {
                SettingsHeroCard().readAloudTarget(L("안내 신호 익히기"),L("조력자와 하나씩 들어보세요"),L("바로가기 버튼")).padding(.top,15).padding(.bottom,27)
                section(L("소리")) {
                    NavigationLink {SoundOutputView()} label: {
                        SettingsRowLabel(title:L("소리 출력"),value:output.name,adaptsToDynamicType:true)
                    }.buttonStyle(.plain).readAloudTarget(L("소리 출력, %@", output.name)).accessibilityIdentifier("settings.output")
                }
                section(L("사용 도움말")) {
                    NavigationLink {V3UsageHelpView()} label: {
                        SettingsRowLabel(title:L("착용과 안내 준비"),adaptsToDynamicType:true)
                    }.buttonStyle(.plain).readAloudTarget(L("착용과 안내 준비")).accessibilityIdentifier("settings.help.wearing")
                    SettingsDivider()
                    NavigationLink {V3SoundHelpView()} label: {
                        SettingsRowLabel(title:L("소리가 들리지 않을 때"),adaptsToDynamicType:true)
                    }.buttonStyle(.plain).readAloudTarget(L("소리가 들리지 않을 때")).accessibilityIdentifier("settings.help.sound")
                    SettingsDivider()
                    NavigationLink {V3VoiceHelpView()} label: {
                        SettingsRowLabel(title:L("음성으로 사용하기"),adaptsToDynamicType:true)
                    }.buttonStyle(.plain).readAloudTarget(L("음성으로 사용하기")).accessibilityIdentifier("settings.help.voice")
                    SettingsDivider()
                    Link(destination:SettingsLinks.support) {
                        SettingsRowLabel(title:L("문의 및 오류 신고"),accessory:.externalLink,adaptsToDynamicType:true)
                    }.buttonStyle(.plain).readAloudTarget(L("문의 및 오류 신고, 외부 웹 페이지 열기")).accessibilityHint(L("문의 및 오류 신고 양식을 브라우저에서 열어요"))
                        .accessibilityIdentifier("settings.support")
                }
                section(L("앱 관리")) {
                    NavigationLink {V3PermissionView()} label: {
                        SettingsRowLabel(title:L("권한 상태"),adaptsToDynamicType:true)
                    }.buttonStyle(.plain).readAloudTarget(L("권한 상태")).accessibilityIdentifier("settings.permissions")
                    SettingsDivider()
                    NavigationLink {LanguageSettingsView()} label: {
                        SettingsRowLabel(title:L("언어 설정"),value:HearLanguage.current.nativeName,adaptsToDynamicType:true)
                    }.buttonStyle(.plain).readAloudTarget(L("언어 설정, %@", HearLanguage.current.nativeName)).accessibilityIdentifier("settings.language")
                    SettingsDivider()
                    SettingsRowLabel(title:L("앱 버전"),value:version,accessory:.none,adaptsToDynamicType:true)
                        .accessibilityElement(children:.combine).readAloudTarget(L("앱 버전, %@", version)).accessibilityIdentifier("settings.version")
                    SettingsDivider()
                    Link(destination:SettingsLinks.privacy) {
                        SettingsRowLabel(title:L("개인정보 처리방침"),accessory:.externalLink,adaptsToDynamicType:true)
                    }.buttonStyle(.plain).readAloudTarget(L("개인정보 처리방침, 외부 웹 페이지 열기")).accessibilityHint(L("개인정보 처리방침을 브라우저에서 열어요"))
                        .accessibilityIdentifier("settings.privacy")
                }
            }.padding(.horizontal,20).padding(.bottom,24)
        }.settingsScreen()
            .navigationTitle(L("설정")).navigationBarTitleDisplayMode(.inline)
            .readsAloud(title:L("설정")) {readAloudLines}
            .onAppear {output.refresh()}
            .onChange(of:scenePhase) {_,phase in if phase == .active {output.refresh()}}
    }
    private var readAloudLines: [String] {
        [L("설정"),L("안내 신호 익히기"),L("조력자와 하나씩 들어보세요"),L("바로가기 버튼"),
         L("소리"),L("소리 출력, %@", output.name),
         L("사용 도움말"),L("착용과 안내 준비"),L("소리가 들리지 않을 때"),L("음성으로 사용하기"),
         L("문의 및 오류 신고, 외부 웹 페이지 열기"),
         L("앱 관리"),L("권한 상태"),L("언어 설정, %@", HearLanguage.current.nativeName),L("앱 버전, %@", version),L("개인정보 처리방침, 외부 웹 페이지 열기")]
    }
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing:0) {
            SettingsSectionHeader(title:title)
            SettingsGroup {content()}
        }.padding(.bottom,24)
    }
}

/// Public destinations shared by the settings links.
enum SettingsLinks {
    static let support=URL(string:"https://docs.google.com/forms/d/e/1FAIpQLSe7ZGjEtVlTH_JErX9-SHIASTyxf8JJCadpgt1ne4meMmrYzg/viewform?usp=publish-editor")!
    static let privacy=URL(string:"https://xrpjwk8.github.io/heariam-help/privacy/")!
}

/// 「안내 신호 익히기」 card with the design's moving background (Liquid Metal + Light rays, see SettingsHeroShader.metal).
struct SettingsHeroCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start=Date()
    var body: some View {
        ZStack {
            TimelineView(.animation(paused:reduceMotion)) { context in
                let seconds=Float(context.date.timeIntervalSince(start))
                GeometryReader { geometry in
                    Rectangle().colorEffect(ShaderLibrary.settingsHero(.float2(geometry.size),.float(seconds)))
                }
            }
            // 58pt symbol, 26pt title, 16pt copy, then a 50pt capsule in plain Liquid Glass 14pt from the card's sides.
            VStack(spacing:0) {
                Image(systemName:"waveform").font(.system(size:44,weight:.regular)).foregroundStyle(.white)
                    .frame(width:58,height:58).accessibilityHidden(true)
                Text(L("안내 신호 익히기")).font(.system(size:26,weight:.semibold)).foregroundStyle(.white).padding(.top,5)
                Text(L("조력자와 하나씩 들어보세요")).font(.system(size:16)).foregroundStyle(.white.opacity(0.8)).padding(.top,3)
                NavigationLink {SoundTestView()} label: {
                    Text(L("바로가기")).font(.system(size:17,weight:.semibold)).foregroundStyle(.white)
                        .frame(maxWidth:.infinity,minHeight:50)
                        .liquidGlass(Capsule())
                        .contentShape(Capsule())
                }.buttonStyle(.plain).padding(.top,28).accessibilityLabel(L("안내 신호 익히기 바로가기"))
                    .accessibilityIdentifier("settings.tutorial")
            }.lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal,14).padding(.vertical,28)
        }.frame(height:255).clipShape(RoundedRectangle(cornerRadius:34,style:.continuous))
            .environment(\.colorScheme,.dark)
    }
}

/// 「언어 설정」 (#183): Korean or English, switched the moment a row is tapped. Screen text, the speaking voice
/// and the voice assistant all follow.
struct LanguageSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing:0) {
                SettingsGroup {
                    ForEach(Array(HearLanguage.allCases.enumerated()),id:\.element) {index,language in
                        if index > 0 {SettingsDivider()}
                        Button {HearLanguage.choose(language)} label: {
                            SettingsRowLabel(title:language.nativeName,accessory:HearLanguage.current == language ? .checkmark : .none)
                        }.buttonStyle(.plain).accessibilityLabel(language.nativeName)
                            .accessibilityAddTraits(HearLanguage.current == language ? [.isSelected] : [])
                            .accessibilityIdentifier("language.\(language.rawValue)")
                    }
                }.padding(.top,15)
            }.padding(.horizontal,16).padding(.bottom,24)
        }.settingsScreen()
            .navigationTitle(L("언어 설정")).navigationBarTitleDisplayMode(.inline)
            .readsAloud(title:L("언어 설정")) {
                [L("언어 설정")]+HearLanguage.allCases.map {$0.nativeName+(HearLanguage.current == $0 ? L(", 선택됨") : "")}
            }
    }
}

/// 「소리 출력」 (Figma 457:13432): output device, playback preference and a volume check.
struct SoundOutputView: View {
    @AppStorage(HearAudioSession.speakerKey) private var forcesSpeaker=false
    @StateObject private var output=SoundOutputStatus()
    @StateObject private var model=SoundTestViewModel()
    @Environment(\.scenePhase) private var scenePhase
    private let test=SignalTutorialExample("output-test",L("시험 소리 듣기"),L("출발 준비 완료 때 들리는 띵 소리"),playback:.arrival)
    var body: some View {
        ScrollView {
            VStack(spacing:0) {
                OutputDeviceHero(output:output)
                OutputDeviceRow(output:output).padding(.top,8).padding(.bottom,16)
                SettingsSectionHeader(title:L("재생 방식"))
                SettingsGroup {
                    option(L("연결된 기기로 자동"),detail:L("이어폰이 없으면 iPhone 스피커로 재생해요."),speaker:false)
                    SettingsDivider()
                    option(L("항상 iPhone 스피커"),detail:L("조력자와 함께 들을 때 사용해요."),speaker:true)
                }.padding(.bottom,16)
                SettingsSectionHeader(title:L("소리 확인"))
                SystemVolumeSlider().padding(.bottom,8)
                SettingsGroup {TutorialExampleRow(example:test,model:model)}
                if let error=model.error {TutorialPlaybackError(message:error).padding(.top,8)}
            }.padding(.horizontal,16).padding(.bottom,24)
        }.settingsScreen()
            .navigationTitle(L("소리 출력")).navigationBarTitleDisplayMode(.inline)
            .readsAloud(title:L("소리 출력")) {
                model.stop()
                return [L("소리 출력"),L("출력 기기, %@", output.name),L("재생 방식"),
                        L("연결된 기기로 자동%@", forcesSpeaker ? "" : L(", 선택됨")),L("항상 iPhone 스피커%@", forcesSpeaker ? L(", 선택됨") : ""),
                        L("소리 확인"),L("음량 조절"),"\(test.title), \(test.detail)"]
            }
            .onAppear {model.appear();output.refresh()}.onDisappear {model.disappear()}
            .onChange(of:forcesSpeaker) {_,_ in model.outputPreferenceChanged();output.refresh()}
            .onChange(of:scenePhase) {_,phase in if phase != .active {model.stop()} else {output.refresh()} }
    }
    private func option(_ title: String, detail: String, speaker: Bool) -> some View {
        Button {forcesSpeaker=speaker} label: {
            SettingsRowLabel(title:title,accessory:forcesSpeaker == speaker ? .checkmark : .none)
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityHint(detail)
            .accessibilityAddTraits(forcesSpeaker == speaker ? [.isSelected] : [])
            .accessibilityIdentifier(speaker ? "output.speaker" : "output.auto")
    }
}
