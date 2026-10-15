import SwiftUI
import PoC4Core

struct PreparationView: View {
    @StateObject private var model=ScanLabModel(preparing:true)
    let onClose: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var step=0
    @State private var highest=0
    @State private var intro: Int? = 0
    @State private var seen: Set<Int> = [0]
    @State private var confirmScan=false
    @State private var confirmExit=false
    @State private var selectedCorner: Int?
    @State private var objectEditing=false
    @State private var review=false
    @State private var guideCollapsed=false
    private let titles=["스캔","무대 범위","장애물","경로","확인점"]
    private let cornerNames=["앞 왼쪽","앞 오른쪽","뒤 오른쪽","뒤 왼쪽"]
    private var draft: PreparationDraft {model.preparation ?? PreparationDraft()}
    private var nextCorner: Int? {selectedCorner ?? PreparationDraft.captureOrder.first(where:{draft.corners[$0] == nil})}
    var body: some View {
        GeometryReader { safe in
        VStack(spacing:0) {
            stepBar
            GeometryReader { geometry in
            ZStack {
                CameraView(model:model).frame(maxWidth:.infinity,maxHeight:.infinity)
                if !model.supported {Color(.systemGray6)}
                if model.supported {
                Image(systemName:"plus").font(.system(size:30,weight:.light)).foregroundStyle(.white).shadow(color:.black,radius:2).accessibilityHidden(true)
                VStack {
                    HStack(alignment:.top) {
                        if step>0 {miniMap.frame(width:180,height:125).padding(10).background(.regularMaterial,in:RoundedRectangle(cornerRadius:18))}
                        Spacer(minLength:70)
                        VStack(spacing:0) {
                            HStack {
                                Text("STEP \(step+1)").font(.caption.bold()).foregroundStyle(.secondary)
                                Spacer()
                                Button {intro=0} label:{Image(systemName:"questionmark.circle")}.accessibilityLabel("단계 안내 다시 보기")
                                Button {guideCollapsed.toggle()} label:{Image(systemName:guideCollapsed ? "chevron.down" : "chevron.up")}.accessibilityLabel(guideCollapsed ? "안내 펼치기" : "안내 접기")
                            }.padding(12)
                            if !guideCollapsed {
                                ScrollView {guideCard}.frame(maxHeight:max(76,geometry.size.height-152))
                            }
                        }.frame(width:min(260,geometry.size.width*0.35)).background(.regularMaterial,in:RoundedRectangle(cornerRadius:20))
                    }
                    Spacer(minLength:8)
                    HStack {
                        Text(model.preparationInterrupted ? "추적 중단" : (step == 0 ? "민트색 그물 = 스캔한 표면" : "십자선을 실제 바닥에 맞춰주세요"))
                            .font(.caption).padding(8).background(.regularMaterial,in:Capsule())
                        Spacer()
                        controls
                    }
                }.padding(.leading,safe.safeAreaInsets.leading+14)
                    .padding(.trailing,safe.safeAreaInsets.trailing+14)
                    .padding(.bottom,safe.safeAreaInsets.bottom+14)
                    .padding(.top,14)
                }
                if let intro, model.supported {
                    Color.black.opacity(0.30)
                    PreparationIntro(step:step,page:intro) {
                        if step == 1 && intro == 0 {self.intro=1} else {self.intro=nil}
                    }.padding(16)
                }
                if !model.supported {
                    ContentUnavailableView("LiDAR 지원 iPhone이 필요해요",systemImage:"camera",description:Text("무대 준비는 실제 카메라와 LiDAR로 공간을 저장합니다. 시뮬레이터에서는 스캔할 수 없어요."))
                        .frame(maxWidth:500).background(.regularMaterial,in:RoundedRectangle(cornerRadius:20))
                }
                if model.preparationInterrupted {
                    VStack(spacing:14) {
                        Label("공간 추적이 잠시 멈췄어요",systemImage:"pause.circle").font(.headline)
                        Text("입력한 정보는 유지됩니다. 같은 공간을 비추고 다시 시작해주세요.").font(.subheadline)
                        ActionButton(title:"추적 다시 시작") {model.resumePreparation()}
                    }.padding(24).background(.regularMaterial,in:RoundedRectangle(cornerRadius:20))
                }
                if review {reviewCard}
                if model.busy && review {
                    Color.black.opacity(0.35)
                    VStack(spacing:16) {ProgressView(); Text("무대 정보를 저장하는 중입니다…").font(.headline)}
                        .padding(32).background(.regularMaterial,in:RoundedRectangle(cornerRadius:22))
                }
            }.frame(width:geometry.size.width,height:geometry.size.height).clipped()
            }.ignoresSafeArea(.container,edges:[.horizontal,.bottom])
        }
        }.background(.white).preferredColorScheme(.light)
            .onAppear {model.showMesh=true; if model.supported {model.newScan()}}
            .onChange(of:step) {_,value in model.showMesh = value == 0}
            .onDisappear {model.endSession()}
            .onChange(of:scenePhase) {_,phase in if phase == .background {model.setActive(false)} else if phase == .active {model.setActive(true)}}
            .onChange(of:model.savedID) {_,id in if id != nil {onClose()}}
            .alert("공간 스캔을 확정할까요?",isPresented:$confirmScan) {
                Button("계속 스캔",role:.cancel) {}
                Button("공간 확정") {model.confirmSpace(); if model.scanConfirmed {advance()}}
            } message:{Text("공연장과 백스테이지가 충분히 포함됐는지 확인해주세요. 확정 후에는 스캔 단계로 돌아갈 수 없습니다.")}
            .alert("확인해주세요",isPresented:Binding(get:{model.errorMessage != nil},set:{if !$0 {model.errorMessage=nil}})) {Button("확인",role:.cancel) {model.errorMessage=nil}} message:{Text(model.errorMessage ?? "")}
            .confirmationDialog("준비를 종료할까요? 저장하지 않은 내용은 사라집니다.",isPresented:$confirmExit,titleVisibility:.visible) {
                Button("저장하지 않고 나가기",role:.destructive) {onClose()}; Button("계속 준비",role:.cancel) {}
            }
    }
    private var stepBar: some View {
        HStack(spacing:12) {
            Text("무대 준비").font(.headline)
            ForEach(0..<5) {i in
                if i>0 {Rectangle().fill(.gray.opacity(0.25)).frame(maxWidth:20).frame(height:1)}
                Button {changeStep(i)} label:{
                    HStack(spacing:5) {
                        Image(systemName:complete(i) ? "checkmark.circle.fill" : (step == i ? "largecircle.fill.circle" : "circle"))
                        Text(titles[i])
                    }.font(.system(size:12,weight:step == i ? .bold : .regular))
                        .foregroundStyle(step == i ? Color.hearInk : .secondary)
                }.disabled(model.busy || i == 0 || i>highest || objectEditing).accessibilityLabel("\(i+1)단계 \(titles[i])\(complete(i) ? ", 완료" : "")")
            }
            Spacer(minLength:0)
            Button("나가기") {if model.meshCount == 0 {onClose()} else {confirmExit=true}}.font(.subheadline).disabled(model.busy)
        }.padding(.horizontal,20).frame(height:52)
    }
    private var miniMap: some View {
        let area=draft.area
        return StageMap(width:area?.width ?? 12,depth:area?.depth ?? 8,
                        points:area.map {a in draft.route.map(a.floor)} ?? [],finished:draft.routeFinished,
                        objects:area.map {a in draft.objects.compactMap {try? $0.projected(in:a)}} ?? [],
                        checkpoint:area.flatMap {a in draft.checkpoint.map(a.floor)},
                        cornerStates:step == 1 ? draft.corners.map {$0 != nil} : nil,
                        activeCorner:step == 1 ? nextCorner : nil)
    }
    private var guideCard: some View {
        VStack(alignment:.leading,spacing:8) {
            Text(guideTitle).font(.system(size:19,weight:.bold))
            Text(guideDescription).font(.system(size:12)).foregroundStyle(.secondary)
            if step == 0 {
                Text("\(model.meshCount)개 표면 · \(model.mapping)").font(.caption).foregroundStyle(.secondary)
                Toggle("스캔 범위 표시",isOn:$model.showMesh).font(.caption).tint(.hearGreen)
            }
            if step == 1 {
                HStack(spacing:5) {ForEach(PreparationDraft.captureOrder,id:\.self) {i in
                    Button(cornerNames[i]) {selectedCorner=i}.font(.system(size:10)).buttonStyle(.bordered).tint(selectedCorner == i ? .hearGreen : .gray)
                }}
                if draft.corners.allSatisfy({$0 != nil}), let error=draft.boundaryErrors.first {Text(error).font(.caption).foregroundStyle(.red)}
            }
            if step == 2 {
                if objectEditing {
                    TextField("기물 이름",text:$model.obstacleName).textFieldStyle(.roundedBorder).font(.caption)
                    Picker("종류",selection:$model.obstacleKind) {Text("장애물").tag(ObstacleKind.other); Text("단상").tag(ObstacleKind.platform)}.pickerStyle(.segmented)
                } else {
                    ScrollView {VStack(spacing:4) {ForEach(draft.objects) {o in
                        HStack {Button(o.name) {model.beginPreparationObject(o.id); objectEditing=true}; Spacer(); Button {model.deletePreparationObject(o.id)} label:{Image(systemName:"trash")}.accessibilityLabel("\(o.name) 삭제")}.font(.caption).padding(.vertical,4)
                    }}}.frame(maxHeight:60)
                }
            }
            if step == 3, draft.routeFinished, let error=draft.routeErrors.first {Text(error).font(.caption).foregroundStyle(.red)}
            if step == 4, draft.checkpoint != nil, let error=draft.checkpointErrors.first {Text(error).font(.caption).foregroundStyle(.red)}
        }.padding(.horizontal,14).padding(.bottom,14)
    }
    private var guideTitle: String {
        switch step {
        case 0:return "공간을 천천히 둘러보세요"
        case 1:return nextCorner.map {"무대 \(cornerNames[$0])을 지정해주세요"} ?? "네 모서리가 연결됐어요"
        case 2:return objectEditing ? "기물의 바닥 둘레를 지정해주세요" : "장애물과 단상을 등록하세요"
        case 3:return draft.routeFinished ? "경로가 연결됐어요" : (draft.route.isEmpty ? "출발점을 지정해주세요" : "다음 위치를 지정해주세요")
        default:return draft.checkpoint == nil ? "확인점 한 개를 지정해주세요" : "확인점을 지정했어요"
        }
    }
    private var guideDescription: String {
        switch step {
        case 0:return "휴대폰을 양손으로 잡고 공연장과 백스테이지까지 충분히 담아주세요."
        case 1:return "객석에서 바라본 기준입니다. 네 점이 자동으로 연결됩니다. 위 이름을 눌러 다시 찍을 수 있어요."
        case 2:return objectEditing ? "십자선을 물체 주변 바닥 모서리에 맞추고 ‘둘레 점 추가’를 누르세요. 한 방향으로 3~8점을 찍고 등록하면 자동으로 닫힙니다. 현재 \(model.pendingObjectWorld.count)/8점 · 윗면은 찍지 않아요." : "‘기물 추가’ 후 바닥 둘레를 직접 찍어요. 사각형은 네 모서리를 순서대로 지정하세요. 기물이 없으면 건너뛰세요."
        case 3:return "출발·도착은 같은 높이의 무대 밖도 가능해요. 내부 지점은 무대 안에 지정하세요. \(draft.route.count)/6점"
        default:return "무대 중앙 또는 특징적인 바닥 지점을 선택하세요. 모서리에서 0.5m 이상 떨어져야 해요."
        }
    }
    @ViewBuilder private var controls: some View {
        switch step {
        case 0:
            ActionButton(title:"공간 확정하기",enabled:model.canConfirmScan) {confirmScan=true}
        case 1:
            if let last=PreparationDraft.captureOrder.last(where:{draft.corners[$0] != nil}) {
                ActionButton(title:"마지막 점 삭제",primary:false,enabled:!model.busy) {model.undoPreparationCorner(last); selectedCorner=nil}
            }
            if let nextCorner {ActionButton(title:"모서리 지정",enabled:model.canPlacePoint) {model.prepareCorner(nextCorner); selectedCorner=nil}}
            if draft.area != nil {ActionButton(title:"다음 단계") {advance()}}
        case 2:
            if objectEditing {
                Button("취소") {model.cancelPreparationObject(); objectEditing=false}.padding(8).background(.regularMaterial,in:Capsule())
                ActionButton(title:"마지막 점 삭제",primary:false,enabled:!model.pendingObjectWorld.isEmpty) {model.undoPreparationObjectVertex()}
                ActionButton(title:"둘레 점 추가",enabled:model.canPlacePoint && model.pendingObjectWorld.count<8) {model.prepareObjectVertex()}
                ActionButton(title:"기물 등록",enabled:model.pendingObjectWorld.count>=3) {if model.commitPreparationObject() {objectEditing=false}}
            } else {
                ActionButton(title:"기물 추가",primary:false,enabled:draft.area != nil) {model.beginPreparationObject(); objectEditing=true}
                ActionButton(title:draft.objects.isEmpty ? "건너뛰기" : "다음 단계",enabled:draft.objectErrors.isEmpty) {advance()}
            }
        case 3:
            if !draft.route.isEmpty {ActionButton(title:"마지막 점 삭제",primary:false) {model.undoPreparationRoute()}}
            if draft.routeFinished {
                ActionButton(title:"다음 단계",enabled:draft.routeErrors.isEmpty) {advance()}
            } else {
                if draft.route.count<5 {ActionButton(title:draft.route.isEmpty ? "출발점 지정" : "P\(draft.route.count) 지정",enabled:model.canPlacePoint && draft.area != nil) {model.prepareRoutePoint()}}
                if draft.route.count>=2 {ActionButton(title:"도착점 지정",enabled:model.canPlacePoint && draft.area != nil) {model.prepareRoutePoint(destination:true)}}
            }
        default:
            ActionButton(title:draft.checkpoint == nil ? "확인점 지정" : "다시 찍기",primary:draft.checkpoint == nil,enabled:model.canPlacePoint && draft.area != nil) {model.prepareCheckpoint()}
            if draft.checkpoint != nil {ActionButton(title:"검토하기",enabled:draft.checkpointErrors.isEmpty) {review=true}}
        }
    }
    private var reviewCard: some View {
        ZStack {
            Color.black.opacity(0.35)
            HStack(spacing:24) {
                miniMap.frame(width:260)
                VStack(alignment:.leading,spacing:12) {
                    Text("무대 정보를 확인해주세요").font(.title3.bold())
                    TextField("무대 이름",text:$model.scanName).textFieldStyle(.roundedBorder)
                    if model.scanName.count>80 {Text("무대 이름은 80자 이내로 입력해주세요.").font(.caption).foregroundStyle(.red)}
                    Text("경로 \(draft.route.count)점 · 기물 \(draft.objects.count)개 · 확인점 1개").font(.subheadline)
                    if draft.errors.isEmpty {Text("저장 준비가 끝났어요. 공간 지도가 안정되면 저장할 수 있습니다.").font(.caption).foregroundStyle(.secondary)}
                    else {ScrollView {Text(Array(Set(draft.errors)).sorted().joined(separator:"\n")).font(.caption).foregroundStyle(.red)}.frame(maxHeight:70)}
                    HStack {
                        ActionButton(title:"돌아가기",primary:false,enabled:!model.busy) {review=false}
                        ActionButton(title:"저장하기",enabled:model.canSave && !model.scanName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && model.scanName.count<=80) {model.save()}
                    }
                }.frame(maxWidth:350)
            }.padding(24).frame(maxWidth:720,maxHeight:260).background(.regularMaterial,in:RoundedRectangle(cornerRadius:24)).padding(16)
        }
    }
    private func complete(_ i:Int) -> Bool {
        switch i {case 0:return model.scanConfirmed; case 1:return draft.area != nil; case 2:return highest>2 && draft.objectErrors.isEmpty; case 3:return draft.routeFinished && draft.routeErrors.isEmpty; default:return draft.checkpoint != nil && draft.checkpointErrors.isEmpty}
    }
    private func advance() {highest=max(highest,min(step+1,4)); changeStep(min(step+1,4))}
    private func changeStep(_ value:Int) {
        guard value>0, value<=highest, !model.busy else {return}
        step=value; review=false; selectedCorner=nil; guideCollapsed=false
        if !seen.contains(value) {seen.insert(value); intro=0} else {intro=nil}
    }
}
