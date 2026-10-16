import SwiftUI
import PoC4Core

struct GuidanceView: View {
    @ObservedObject var library: StageLibrary
    @StateObject private var model=GuidanceModel()
    @State private var savingRecord=false
    @State private var saveError: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(alignment:.leading,spacing:12) {
                Text(stepLabel).font(.subheadline.weight(.semibold)).foregroundStyle(Color.hearGreen).padding(.horizontal,24)
                if model.showsRouteCamera { routeCameraHeader }
                ZStack {
                    // Keep one AR view attached throughout the flow, including when the screen shows instructions.
                    CameraView(model:model.tracking).frame(maxWidth:.infinity,maxHeight:.infinity).accessibilityHidden(true)
                    if model.showsRouteCamera { routeCameraOverlay }
                    else if model.isCameraStep { cameraContent }
                    else { Color(.systemBackground); content }
                }.clipShape(RoundedRectangle(cornerRadius:model.showsRouteCamera ? 18 : 0))
                    .padding(.horizontal,model.showsRouteCamera ? 20 : 0)
            }
            .navigationTitle("안내 사용하기").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    Button("나가기",systemImage:"xmark") { exit() }.labelStyle(.iconOnly)
                        .disabled(model.phase == .finishing || savingRecord || (model.phase == .completed && model.speaking))
                }
            }
            .safeAreaInset(edge:.bottom,spacing:0) { controls }
            .background(Color(.systemBackground))
            .alert("안내를 끝낼까요?",isPresented:$model.showExit) {
                Button("안내 끝내기",role:.destructive) { model.finish();dismiss() }
                Button("계속 사용하기",role:.cancel) { model.cancelExit() }
            } message: { Text("중간에 종료하면 도착 완료로 처리되지 않아요. 저장한 무대와 동선은 유지돼요.") }
        }
        .interactiveDismissDisabled()
        .onAppear {ScreenOrientation.set(.portrait)}
        .task {await library.refresh();model.selectionDescription(empty:library.records.isEmpty)}
        .onDisappear {model.finish();ScreenOrientation.set(.portrait)}
        .onChange(of:scenePhase) { _, value in
            // Camera permission sheets may make the scene inactive during restoration.
            if value == .active { model.setActive(true) }
            else if value == .background || (model.phase != .selection && model.phase != .restoring) { model.setActive(false) }
        }
    }
    private var stepLabel: String {
        switch model.phase {
        case .selection:return "1 / 4 · 무대 선택"
        case .restoring,.checkpoint,.failed:return "2 / 4 · 현장 확인"
        case .wear,.countdown:return "3 / 4 · 허리띠 착용"
        case .departure,.starting:return "4 / 4 · 출발 준비"
        case .guiding:return "안내 중 · \(model.targetName)"
        case .paused:return "안내 일시정지"
        case .interrupted:return "안내 중단 · 재확인 필요"
        case .finishing,.completed:return "안내 완료"
        }
    }
    @ViewBuilder private var content: some View {
        if model.phase == .selection { selection }
        else {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    illustration
                    Text(title).font(.largeTitle.bold()).fixedSize(horizontal:false,vertical:true)
                    Text(detail).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    if let selected=model.selected { Text(selected.name).font(.subheadline).foregroundStyle(.secondary) }
                    if model.phase == .departure {
                        Label(model.tracking.ready ? "확인점 검증 완료" : "위치 확인 중",systemImage:model.tracking.ready ? "checkmark.circle.fill" : "circle")
                        Label(model.tracking.heading != nil ? "몸의 방향 확인 완료" : "카메라를 몸 바깥쪽으로 향해주세요",systemImage:"location.north")
                        if let distance=model.startDistance, !model.hasStarted { Text("출발점까지 \(distance,format:.number.precision(.fractionLength(1))) m").font(.headline.monospacedDigit()) }
                        Text(model.hasStarted ? "안내를 중단했던 동선 위에서 재개할 수 있어요." : "출발점까지의 별도 길 안내는 제공하지 않아요. 출발점에서 잠시 멈춰주세요. 어느 방향을 바라봐도 몸의 방향에 맞춰 안내해요.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if model.phase == .failed {
                        Text("저장한 공연장인지 확인해주세요. 카메라 권한은 설정 앱에서 변경할 수 있어요.").font(.footnote).foregroundStyle(.secondary)
                        Button("앱 설정 열기") {if let url=URL(string:UIApplication.openSettingsURLString) {UIApplication.shared.open(url)}}
                    }
                }.frame(maxWidth:.infinity,alignment:.leading).padding(24)
            }
        }
    }
    private var selection: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Text("저장한 공연장에서\n안내를 시작해요").font(.largeTitle.bold())
                if library.loading {ProgressView("저장한 무대를 불러오고 있어요")}
                if library.records.isEmpty && !library.loading {
                    Image("StageEmpty").resizable().scaledToFit().frame(height:180).accessibilityHidden(true)
                    Text("저장된 무대가 아직 없어요").font(.title2.bold())
                    Text("홈에서 무대 준비하기를 통해 공간과 동선을 먼저 저장해주세요.").foregroundStyle(.secondary)
                }
                if !library.groups.pinned.isEmpty { stageGroup("고정한 무대",items:library.groups.pinned) }
                if !library.groups.recent.isEmpty { stageGroup("최근 저장한 무대",items:library.groups.recent) }
                if let error=library.error { Text(error).font(.footnote).foregroundStyle(.red);Button("목록 다시 불러오기") {Task {await library.refresh()}} }
                Text("현장에서 스캔한 무대만 사용할 수 있어요. 공연 사전 도면은 포함되지 않아요.").font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }
    }
    private func stageGroup(_ title: String,items: [ScanManifest]) -> some View {
        VStack(alignment:.leading,spacing:12) {
            Text(title).font(.headline)
            ForEach(items,id:\.id) { item in
                let usable=item.route.map {$0.conflicts(boundaryMargin:item.settings.boundaryMargin,obstacleClearance:item.settings.obstacleClearance).isEmpty} ?? false
                Button {model.select(item)} label: {
                    VStack(alignment:.leading,spacing:12) {
                    HStack(alignment:.top,spacing:12) {
                        Image(systemName:model.selected?.id == item.id ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(Color.hearGreen)
                        VStack(alignment:.leading,spacing:8) {
                            Text(item.name).font(.headline).multilineTextAlignment(.leading)
                            Text(usable ? "내부 지점 \(max(0,(item.route?.points.count ?? 2)-2))개 · 기물 \(item.route?.obstacles.count ?? 0)개" : "사용할 동선이 없어요 · 무대 다시 준비 필요")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(item.date.formatted(.dateTime.locale(Locale(identifier:"ko_KR")).month().day().hour().minute())+" 저장").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength:0)
                        if library.pins.ids.contains(item.id) {Image(systemName:"star.fill").accessibilityLabel("고정한 무대")}
                    }
                    if model.selected?.id == item.id, let route=item.route {
                        StageMap(width:route.area.width,depth:route.area.depth,points:route.points,objects:route.obstacles)
                            .frame(height:140).accessibilityHidden(true)
                    }
                    }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
                        .background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:18))
                        .overlay(RoundedRectangle(cornerRadius:18).stroke(model.selected?.id == item.id ? Color.hearGreen : .clear,lineWidth:2))
                }.buttonStyle(.plain).disabled(!usable)
                    .accessibilityAddTraits(model.selected?.id == item.id ? [.isSelected] : [])
            }
        }
    }
    private var routeCameraHeader: some View {
        HStack(alignment:.top,spacing:16) {
            Image(systemName:symbol).font(.system(size:42,weight:.medium)).foregroundStyle(Color.hearGreen)
                .frame(width:56).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:7) {
                Text(title.replacingOccurrences(of:"\n",with:" ")).font(.title2.bold()).fixedSize(horizontal:false,vertical:true)
                Text(detail).font(model.phase == .guiding ? .title2 : .subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal:false,vertical:true)
            }
            Spacer(minLength:0)
        }.padding(.horizontal,24).padding(.vertical,8)
    }
    private var routeCameraOverlay: some View {
        VStack {
            HStack {
                Label("실시간 카메라 · 검증용",systemImage:"camera").font(.caption.weight(.semibold))
                Spacer()
            }.padding(10).background(.regularMaterial)
            Spacer()
            if !model.tracking.ready {
                Label("위치 확인 필요 · 지점 표시를 확인할 수 없어요",systemImage:"exclamationmark.triangle")
                    .font(.caption).padding(12).frame(maxWidth:.infinity).background(.regularMaterial)
            } else {
                HStack(spacing:12) {
                    Label("저장 지점",systemImage:"circle.fill").foregroundStyle(Color.hearGreen)
                    if model.phase != .finishing && model.phase != .completed {
                        Label("현재 목표",systemImage:"scope").foregroundStyle(.orange)
                    }
                    Spacer(minLength:0)
                }.font(.caption.bold()).padding(12).background(.regularMaterial)
            }
        }.allowsHitTesting(false)
    }
    private var cameraContent: some View {
        ZStack {
            Image(systemName:"plus").font(.system(size:30,weight:.medium)).foregroundStyle(.white)
                .shadow(color:.black,radius:2).accessibilityHidden(true)
            VStack {
                HStack {Label(model.phase == .restoring ? "공간 확인 중" : "확인점 검증",systemImage:"camera");Spacer()}
                    .font(.caption.weight(.semibold)).padding(12).background(.regularMaterial,in:Capsule())
                Spacer()
                VStack(alignment:.leading,spacing:10) {
                    if model.phase == .restoring {ProgressView()}
                    Text(model.phase == .restoring ? "공연장을 찾고 있어요" : "저장한 확인점에\n조준점을 맞춰주세요").font(.title2.bold())
                    Text(model.phase == .restoring ? "휴대폰을 손에 들고 주변을 천천히 비춰주세요." : model.message).font(.subheadline)
                    if model.phase == .checkpoint && !model.tracking.canVerify { Text("위치 추적이 안정될 때까지 기다려주세요.").font(.caption) }
                }.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(.regularMaterial,in:RoundedRectangle(cornerRadius:22))
            }.padding(20)
        }
    }
    @ViewBuilder private var illustration: some View {
        if model.phase == .wear { Image("BeltAction").resizable().scaledToFit().frame(height:170).frame(maxWidth:.infinity).accessibilityHidden(true) }
        else if model.phase == .countdown { Text("\(model.countdown)").font(.system(size:100,weight:.semibold,design:.rounded)).monospacedDigit().frame(maxWidth:.infinity).foregroundStyle(Color.hearGreen) }
        else {
            Image(systemName:symbol).font(.system(size:72,weight:.medium)).foregroundStyle(model.phase == .failed || model.phase == .interrupted ? .red : Color.hearGreen)
                .frame(maxWidth:.infinity).padding(.vertical,24).accessibilityHidden(true)
        }
    }
    private var symbol: String {
        switch model.phase {
        case .guiding:return model.cue?.symbol ?? "location.north"
        case .paused:return "pause.circle"
        case .interrupted,.failed:return "exclamationmark.circle"
        case .finishing,.completed:return "checkmark.circle"
        case .departure:return model.departureReady ? "checkmark.circle" : "location.circle"
        default:return "speaker.wave.2"
        }
    }
    private var title: String {
        switch model.phase {
        case .wear:return "휴대폰을 허리 앞에\n세로로 고정해주세요"
        case .countdown:return "천천히 착용해주세요"
        case .departure:return model.departureReady ? "\(model.hasStarted ? "재개" : "출발") 준비가\n완료됐어요" : "\(model.hasStarted ? "저장한 동선 위에서" : "지정한 출발점에서")\n준비해주세요"
        case .starting:return "안내를 시작할게요"
        case .guiding:return model.arrivedName.map {"\($0)에 도착했어요"} ?? model.cue?.direction ?? "\(model.targetName)으로 이동해요"
        case .paused:return "안내를\n일시정지했어요"
        case .interrupted:return "잠시 멈춰주세요"
        case .failed:return "공연장을\n확인하지 못했어요"
        case .finishing:return "마지막 지점에\n도착했어요"
        case .completed:return "모든 동선을\n완료했어요"
        default:return ""
        }
    }
    private var detail: String {
        switch model.phase {
        case .wear:return "후면 카메라는 몸 바깥쪽으로, 렌즈가 가려지지 않게 해주세요."
        case .countdown:return "착용 시간이 끝나면 위치와 방향을 확인해요."
        case .departure:return model.departureReady ? "하단 버튼을 누르면 \(model.targetName)으로 안내해요." : model.departureStatus
        case .starting:return "시작 음성이 끝나면 방향과 거리를 알려드려요."
        case .guiding:return model.cue.map {model.arrivedName != nil ? "다음 지점 · \($0.direction) " + String(format:"%.1f m",$0.distance) : String(format:"%.1f m",$0.distance)} ?? "위치 확인 중"
        default:return model.message
        }
    }
    private var controls: some View {
        VStack(spacing:10) {
            if let saveError {Text(saveError).font(.footnote).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)}
            if savingRecord {ProgressView("완료 기록을 저장하고 있어요")}
            if let error=model.audioIssue {Text(error).font(.footnote).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true)}
            if model.speaking {
                HStack(alignment:.top,spacing:8) {
                    Image(systemName:"speaker.wave.2.fill").foregroundStyle(Color.hearGreen)
                    Text(model.spokenText).font(.caption).lineLimit(3)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            if model.phase != .starting && model.phase != .countdown && !(model.phase == .finishing && model.speaking) {
                Button {model.replay()} label: {
                    Label(model.phase == .finishing ? "종료 안내 다시 듣기" : "설명 다시 듣기",systemImage:"speaker.wave.2")
                        .font(.subheadline.weight(.medium)).frame(minHeight:44).padding(.horizontal,12)
                }.buttonStyle(.plain).foregroundStyle(Color.hearGreen)
                    .disabled(model.speaking || savingRecord)
                    .opacity(model.speaking || savingRecord ? 0.45 : 1)
            }
            primaryControls
        }.padding(.horizontal,24).padding(.top,12).padding(.bottom,12).background(.regularMaterial)
    }
    @ViewBuilder private var primaryControls: some View {
        switch model.phase {
        case .selection:
            if library.records.isEmpty {GuidanceButton(title:"홈으로 돌아가기") {model.finish();dismiss()}}
            else {GuidanceButton(title:"이 무대 사용하기",enabled:model.selected != nil && model.instructionDone && !model.speaking) {model.restore()}}
        case .restoring: GuidanceButton(title:"공간 확인 중…",enabled:false) {}
        case .checkpoint: GuidanceButton(title:"확인점 확인하기",enabled:model.canVerify) {model.verifyCheckpoint()}
        case .wear: GuidanceButton(title:"착용 준비 시작",enabled:model.instructionDone && !model.speaking) {model.beginWear()}
        case .countdown: GuidanceButton(title:"착용 시간 다시 시작",secondary:true) {model.beginWear()}
        case .departure: GuidanceButton(title:model.hasStarted ? "안내 다시 시작" : "안내 시작",enabled:model.departureReady && model.instructionDone && !model.speaking) {model.startGuidance()}
        case .starting,.guiding: GuidanceButton(title:"일시정지") {model.pause()}
        case .paused:
            GuidanceButton(title:"확인점 다시 확인",secondary:true) {model.restore()}
            GuidanceButton(title:"안내 다시 시작",enabled:model.canResume && model.instructionDone && !model.speaking) {model.startGuidance()}
        case .interrupted:
            GuidanceButton(title:"확인점 다시 확인") {model.restore()}
        case .failed:
            GuidanceButton(title:"무대 다시 선택",secondary:true) {model.chooseAgain()}
            GuidanceButton(title:"공간 다시 확인",enabled:!model.tracking.busy) {model.restore()}
        case .finishing: GuidanceButton(title:"안내 종료 중…",enabled:false) {}
        case .completed: GuidanceButton(title:saveError == nil ? "종료하고 기록 저장" : "기록 저장 다시 시도",enabled:!model.speaking && !savingRecord) {saveAndFinish()}
        }
    }
    private func saveAndFinish() {
        guard !savingRecord else {return}
        savingRecord=true;saveError=nil
        Task {
            defer {savingRecord=false}
            do {
                let record=try model.completedRecord()
                try await library.saveGuidanceRecord(record)
                model.finish();dismiss()
            } catch {saveError="기록을 저장하지 못했어요. 다시 시도해주세요. \(error.localizedDescription)"}
        }
    }
    private func exit() {
        if model.phase == .completed {saveAndFinish()}
        else if model.phase == .selection {model.finish();dismiss()}
        else {model.requestExit()}
    }
}
