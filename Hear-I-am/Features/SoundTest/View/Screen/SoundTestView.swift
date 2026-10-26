import SwiftUI
import HearIAmCore

/// Select any lesson directly. This lives inside Settings, not a tab or a nested NavigationStack.
struct SoundTestView: View {
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                Text("처음에는 조력자와 함께\n편한 속도로 들어보세요.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                TutorialOutputLink()
                VStack(spacing:0) {
                    ForEach(SoundTestSection.allCases) { step in
                        NavigationLink {SignalLessonView(step:step)} label: {
                            HStack(spacing:14) {
                                Text(String(format:"%02d",step.id)).font(.system(size:17,weight:.medium)).monospacedDigit()
                                    .frame(width:42,height:42).background(Color(.systemGray6),in:Circle()).accessibilityHidden(true)
                                VStack(alignment:.leading,spacing:6) {
                                    Text(step.title).font(.headline)
                                    Text(step.subtitle).font(.subheadline).foregroundStyle(.secondary)
                                }.fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                                Image(systemName:"chevron.right").font(.system(size:13)).foregroundStyle(.secondary).accessibilityHidden(true)
                            }.padding(16).frame(minHeight:84).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("\(step.id)단계, \(step.title)").accessibilityHint(step.subtitle)
                            .accessibilityIdentifier("tutorial.step.\(step.id)")
                        if step.next != nil {Divider().padding(.leading,72)}
                    }
                }.background(Color(.systemBackground),in:RoundedRectangle(cornerRadius:20))
                    .overlay(RoundedRectangle(cornerRadius:20).stroke(Color(.systemGray5),lineWidth:1))
            }.padding(20)
        }.background(Color(.systemGroupedBackground))
            .navigationTitle("안내 신호 익히기").navigationBarTitleDisplayMode(.large)
            .toolbar(.hidden,for:.tabBar).tint(.hearInk)
    }
}

struct SignalLessonView: View {
    @State var step: SoundTestSection
    @StateObject private var model=SoundTestViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AccessibilityFocusState private var headingFocused: Bool
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    VStack(alignment:.leading,spacing:8) {
                        Text("\(step.id) / \(SoundTestSection.allCases.count) 단계").font(.subheadline).foregroundStyle(.secondary)
                        HStack(spacing:6) {
                            ForEach(SoundTestSection.allCases) { item in
                                Capsule().fill(item.id <= step.id ? Color.hearInk : Color(.systemGray5)).frame(height:5)
                            }
                        }.accessibilityHidden(true)
                    }.id("lesson-top")
                    Text(step.question).font(.largeTitle.bold()).fixedSize(horizontal:false,vertical:true)
                        .accessibilityAddTraits(.isHeader).accessibilityFocused($headingFocused)
                    Text(step.explanation).font(.body).fixedSize(horizontal:false,vertical:true)
                    if step == .preparation {TutorialOutputLink()}
                    Button {model.explain(step)} label: {
                        Label(model.activeID == "explanation-\(step.id)" ? "설명 중지" : "설명 듣기",systemImage:model.activeID == "explanation-\(step.id)" ? "stop.fill" : "speaker.wave.2")
                            .font(.subheadline.weight(.semibold)).padding(.horizontal,18).frame(minHeight:48)
                            .background(Color(.systemGray6),in:Capsule())
                    }.buttonStyle(.plain).accessibilityIdentifier("tutorial.explanation")
                    if let error=model.error {TutorialPlaybackError(message:error)}
                    ForEach(step.groups) { group in
                        VStack(alignment:.leading,spacing:10) {
                            Text(group.title).font(.headline).accessibilityAddTraits(.isHeader)
                            ForEach(group.examples) {TutorialExampleRow(example:$0,model:model)}
                        }
                    }
                    VStack(alignment:.leading,spacing:8) {
                        Text(step == .arrival ? "공연 대기는 이렇게 진행돼요" : "함께 확인해요").font(.headline)
                        Text(step.together).font(.subheadline).fixedSize(horizontal:false,vertical:true)
                    }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
                        .background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:18))
                }.padding(20)
            }.onChange(of:step) {_,_ in
                model.stop();model.clearError();proxy.scrollTo("lesson-top",anchor:.top);headingFocused=true
            }
        }.background(Color(.systemBackground))
            .navigationTitle(step.title).navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden,for:.tabBar).tint(.hearInk)
            .safeAreaInset(edge:.bottom) {
                HStack(spacing:12) {
                    Button {if let previous=step.previous {step=previous}} label: {
                        Text("이전").font(.headline).frame(maxWidth:.infinity,minHeight:52)
                            .background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:14))
                    }.disabled(step.previous == nil).opacity(step.previous == nil ? 0.4 : 1).accessibilityIdentifier("tutorial.previous")
                    Button {
                        model.stop()
                        if let next=step.next {step=next} else {dismiss()}
                    } label: {
                        Text(step.next == nil ? "목록으로" : "다음").font(.headline).frame(maxWidth:.infinity,minHeight:52)
                            .foregroundStyle(.white).background(Color.hearInk,in:RoundedRectangle(cornerRadius:14))
                    }.accessibilityIdentifier("tutorial.next")
                }.buttonStyle(.plain).padding(.horizontal,20).padding(.vertical,12).background(Color(.systemBackground))
            }
            .onAppear {model.appear()}.onDisappear {model.disappear()}
            .onChange(of:scenePhase) {_,phase in if phase != .active {model.stop()} }
    }
}
