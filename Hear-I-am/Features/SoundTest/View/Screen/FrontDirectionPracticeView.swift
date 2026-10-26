import SwiftUI
import HearIAmCore

struct FrontDirectionPracticeView: View {
    @StateObject private var model = FrontDirectionPracticeViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @AccessibilityFocusState private var issueFocused: Bool

    private var title: String {
        if !model.isRunning { return "연습을 잠시 멈췄어요" }
        switch model.practice.phase {
        case .needsReference: return "앞을 향해 서주세요"
        case .turnAway: return "몸을 조금 돌려보세요"
        case .finding: return "소리를 따라 정면을 찾아보세요"
        case .completed: return "방향이 맞았어요"
        }
    }
    private var instruction: String {
        switch model.practice.phase {
        case .needsReference: return "휴대폰을 실제 안내 때처럼 몸에 고정하고, 조력자와 함께 기준이 될 정면을 정해주세요."
        case .turnAway: return "발은 제자리에 두고 몸을 왼쪽이나 오른쪽으로 돌려보세요. 정면에서 충분히 벗어나면 방향 안내가 시작돼요."
        case .finding: return "낮은 톡은 왼쪽, 높은 톡은 오른쪽이에요. 정면에 가까워질수록 빨라지고, 방향이 맞으면 확인 소리가 들려요."
        case .completed: return "지정한 정면으로 돌아왔어요. 같은 방향으로 다시 연습하거나 새로운 정면을 지정할 수 있어요."
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("제자리에서 몸 방향을 맞춰보세요.").font(.subheadline).foregroundStyle(.secondary)
                indicator.frame(maxWidth: .infinity).padding(.vertical, 8).accessibilityHidden(true)
                Text(title).font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(instruction).font(.body).fixedSize(horizontal: false, vertical: true)
                if let issue = model.issue { TutorialPlaybackError(message: issue).accessibilityFocused($issueFocused) }
                else if model.isRunning, !model.canSetReference {
                    Label("몸 방향을 확인하고 있어요", systemImage: "iphone").font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("함께 확인해요").font(.headline)
                    Text("고개나 눈의 시선이 아닌, 휴대폰을 착용한 몸 방향을 확인해요. 휴대폰의 착용 위치를 바꾸면 정면을 다시 지정해주세요.")
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 18))
            }.padding(20)
        }.background(Color(.systemBackground))
            .navigationTitle("정면 찾기 연습").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar).tint(.hearInk)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button(action: primaryAction) {
                        Text(primaryTitle).font(.headline).multilineTextAlignment(.center)
                            .padding(.horizontal, 14).padding(.vertical, 16).frame(maxWidth: .infinity, minHeight: 54)
                            .foregroundStyle(.white).background(Color.hearInk, in: RoundedRectangle(cornerRadius: 14))
                    }.disabled(model.isRunning && model.practice.phase == .needsReference && !model.canSetReference)
                        .opacity(model.isRunning && model.practice.phase == .needsReference && !model.canSetReference ? 0.4 : 1)
                        .accessibilityIdentifier("practice.primary")
                    if model.practice.referenceHeading != nil {
                        Button("정면 다시 지정") { model.resetReference() }
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                            .accessibilityIdentifier("practice.reset")
                    }
                }.buttonStyle(.plain).padding(.horizontal, 20).padding(.vertical, 12).background(Color(.systemBackground))
            }
            .onAppear { visible = true; model.start() }
            .onDisappear { visible = false; model.close() }
            .onChange(of: scenePhase) { _, phase in
                guard visible else { return }
                if phase == .active { model.start() }
                else { model.suspend("연습을 잠시 멈췄어요. 다시 정면을 지정해주세요.") }
            }
            .onChange(of: model.issue) { _, issue in
                if issue != nil { issueFocused = true }
            }
    }
    private var indicator: some View {
        ZStack {
            Circle().stroke(Color(.systemGray5), lineWidth: 2)
            if model.practice.phase == .completed {
                Image(systemName: "checkmark").font(.system(size: 58, weight: .medium))
            } else {
                Image(systemName: "arrow.up").font(.system(size: 60, weight: .medium))
                    .rotationEffect(.degrees(model.practice.bearing ?? 0))
            }
        }.frame(width: 168, height: 168)
    }
    private var primaryTitle: String {
        if !model.isRunning { return "다시 시작" }
        switch model.practice.phase {
        case .needsReference: return "이 방향을 정면으로 지정"
        case .turnAway, .finding: return "연습 중지"
        case .completed: return "같은 정면으로 다시 연습"
        }
    }
    private func primaryAction() {
        if !model.isRunning { model.start(); return }
        switch model.practice.phase {
        case .needsReference: model.setReference()
        case .turnAway, .finding: model.suspend("연습을 중지했어요. 다시 시작해서 정면을 지정할 수 있어요.")
        case .completed: model.repeatExercise()
        }
    }
}
