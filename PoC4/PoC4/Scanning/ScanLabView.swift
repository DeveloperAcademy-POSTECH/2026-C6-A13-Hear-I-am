import SwiftUI
import ARKit
import PoC4Core

struct CameraView: UIViewRepresentable {
    let model: ScanLabModel
    func makeUIView(context: Context) -> ARSCNView {
        let view=ARSCNView(frame:.zero)
        view.preferredFramesPerSecond=30
        model.attach(view)
        return view
    }
    func updateUIView(_ uiView: ARSCNView,context:Context) {}
}

struct ScanLabView: View {
    @StateObject private var model=ScanLabModel()
    @State private var showPreview=false
    @Environment(\.scenePhase) private var scenePhase
    private let cornerNames=["앞왼쪽","앞오른쪽","뒤오른쪽","뒤왼쪽"]
    private var guideStateLabel: String {
        switch model.guideState {
        case .idle: return "시작 전"
        case .guiding: return "안내 중"
        case .paused: return "일시정지"
        case .completed: return "완료"
        }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing:0) {
                ZStack {
                    CameraView(model:model)
                    Image(systemName:"plus").font(.title).foregroundStyle(.white)
                        .shadow(color:.black,radius:2).accessibilityHidden(true)
                    VStack {Spacer(); Text("십자선 중심을 실제 무대 바닥에 맞추세요")
                        .font(.caption).padding(6).background(.black.opacity(0.65)).foregroundStyle(.white)}
                }
                .frame(height:240)
                .clipShape(RoundedRectangle(cornerRadius:12))
                .padding(.horizontal)
                .padding(.top,8)
                ScrollView {
                    VStack(alignment:.leading,spacing:16) {
                        Text("PoC4-2 · 현장 경로 안내").font(.title2.bold())
                        Text("LiDAR 무대 스캔 · 수동 경로·장애물 등록 · 배 착용 음성 안내")
                            .font(.footnote).foregroundStyle(.secondary)
                    Button {showPreview=true} label: {Label("스캔 공간·E·경로 3D 보기",systemImage:"cube.transparent")}
                        .disabled(model.meshCount == 0)
                    if !model.supported {
                        Label("LiDAR 지원 실제 iPhone이 필요합니다. 시뮬레이터는 UI·빌드 확인용입니다.",systemImage:"info.circle")
                            .foregroundStyle(.orange)
                    }
                    Text(model.status).font(.headline).accessibilityIdentifier("lab-status")
                    HStack {Text("추적: \(model.tracking)"); Spacer(); Text("지도: \(model.mapping)")}.font(.caption)
                    Text("메시 \(model.meshCount)개 · 정점 \(model.vertexCount)개").font(.caption.monospacedDigit())
                    Toggle("메시 표시",isOn:$model.showMesh).font(.footnote)
                    GroupBox("1. 스캔과 무대 E") {
                        VStack(alignment:.leading,spacing:10) {
                            TextField("스캔 이름",text:$model.scanName).textFieldStyle(.roundedBorder)
                            Button("새 스캔 시작",action:model.newScan).disabled(!model.supported || model.busy)
                            Text("객석 기준 앞왼쪽 → 앞오른쪽 → 뒤오른쪽 → 뒤왼쪽 순서로 찍습니다. 각 버튼을 다시 누르면 해당 점을 수정합니다. 앞 변으로 정면을 정의합니다. 찍은 점은 카메라 화면에 E1~E4 앵커로 표시됩니다. 두 번째 점부터 주황색 점선은 앞 변에 수직인 임시 안쪽 방향이며 E의 확정 경계가 아닙니다.").font(.footnote)
                            ForEach(0..<4,id:\.self) {i in
                                HStack {
                                    Button("\(i+1). \(cornerNames[i]) 선택") {model.captureCorner(i)}
                                    Text(model.corners[i] == nil ? "—" : "✓")
                                }.disabled(model.mode != .scanning || model.busy)
                            }
                            Text(model.references).font(.caption)
                            Text("E는 동일 평면·순서·자기 교차·직각·대변 길이 오차를 검사합니다.").font(.caption)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                    GroupBox("2. 바닥 경로 p0 → p1~p5") {
                        VStack(alignment:.leading,spacing:10) {
                            Text("p0는 출발점, 이후 최대 다섯 목적지입니다. 순서대로 바닥을 찍고 개별 수정·삭제할 수 있습니다.").font(.footnote)
                            Button(model.routePoints.isEmpty ? "p0 찍기" : "p\(model.routePoints.count) 찍기") {model.captureRoutePoint()}
                                .disabled(model.mode != .scanning || model.corners.contains(where:{$0 == nil}) || model.routePoints.count >= 6)
                            ForEach(Array(model.routePoints.enumerated()),id:\.offset) {i,p in
                                HStack {
                                    Text(String(format:"p%d · %.2f, %.2f m",i,p.x,p.y)).monospacedDigit()
                                    Spacer()
                                    Button("수정") {model.captureRoutePoint(i)}
                                    Button("삭제",role:.destructive) {model.removeRoutePoint(i)}
                                }.font(.caption)
                            }
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                    GroupBox("3. 장애물 영역") {
                        VStack(alignment:.leading,spacing:10) {
                            Text("장애물이 없으면 이 단계는 건너뛰세요. 물체가 있다면 바닥 점유 영역의 꼭짓점 3~8개를 둘러 찍습니다. 메시만으로 자동 등록되지 않으며 계단도 통과 금지입니다.").font(.footnote)
                            TextField("물체 이름",text:$model.obstacleName).textFieldStyle(.roundedBorder)
                            Picker("종류",selection:$model.obstacleKind) {
                                Text("계단").tag(ObstacleKind.stairs)
                                Text("박스").tag(ObstacleKind.box)
                                Text("기타").tag(ObstacleKind.other)
                            }.pickerStyle(.segmented)
                            HStack {
                                Button("영역 꼭짓점 추가") {model.captureObstacleVertex()}
                                Button("마지막 점 취소") {model.removeLastObstacleVertex()}
                                    .disabled(model.obstacleDraft.isEmpty)
                            }.disabled(model.mode != .scanning)
                            Text("작성 중: \(model.obstacleDraft.count)개").font(.caption)
                            ForEach(Array(model.obstacleDraft.enumerated()),id:\.offset) {i,p in
                                HStack {
                                    Text(String(format:"영역 %d · %.2f, %.2f m",i+1,p.x,p.y)).font(.caption.monospacedDigit())
                                    Spacer()
                                    Button("수정") {model.captureObstacleVertex(i)}
                                    Button("삭제",role:.destructive) {model.removeObstacleVertex(i)}
                                }.disabled(model.mode != .scanning)
                            }
                            Button("통과 금지 장애물 등록") {model.registerObstacle()}
                                .disabled(model.obstacleDraft.count < 3 || model.mode != .scanning)
                            ForEach(Array(model.obstacles.enumerated()),id:\.element.id) {i,o in
                                HStack {
                                    Text("\(o.name) · \(o.kind.rawValue) · 통과 금지").font(.caption)
                                    Spacer()
                                    Button("수정") {model.editObstacle(i)}
                                    Button("삭제",role:.destructive) {model.removeObstacle(i)}
                                }
                            }
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                    GroupBox("4. 경로 검사와 저장") {
                        VStack(alignment:.leading,spacing:10) {
                            Text("경계 여유 \(model.settings.boundaryMargin,format:.number.precision(.fractionLength(2)))m · 장애물 여유 \(model.settings.obstacleClearance,format:.number.precision(.fractionLength(2)))m").font(.caption)
                            Stepper("경계 여유",value:$model.settings.boundaryMargin,in:0.10...1.0,step:0.05).disabled(model.mode != .scanning)
                            Stepper("장애물 여유",value:$model.settings.obstacleClearance,in:0.10...1.0,step:0.05).disabled(model.mode != .scanning)
                            ForEach(model.routeConflicts,id:\.self) {Text("⚠️ \($0)").font(.caption).foregroundStyle(.red)}
                            Text("E 꼭짓점과 다른 실제 바닥점 C를 선택하세요. E 안쪽도 가능하며 복원 후 같은 지점을 다시 찾을 수 있어야 합니다.").font(.footnote)
                            Button("독립 확인점 C 선택") {model.capture("C")}
                                .disabled(model.mode != .scanning || model.corners.contains(where:{$0 == nil}))
                            Button("메시·지도·E·경로 저장",action:model.save).disabled(!model.canSave || model.busy)
                            Text("mapped, 메시, C, 최소 p0→p1, 충돌 없는 모든 선분이 필요합니다.").font(.caption)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                    GroupBox("5. 저장 공간 복원과 C 검증") {
                        VStack(alignment:.leading,spacing:10) {
                            if model.records.isEmpty {Text("저장된 스캔이 없습니다.").foregroundStyle(.secondary)}
                            ForEach(model.records,id:\.id) {item in
                                Button {model.restore(item)} label: {
                                    VStack(alignment:.leading) {
                                        Text(item.name).font(.headline)
                                        Text("\(item.date.formatted()) · 메시 \(item.meshCount) · v\(item.version)").font(.caption)
                                    }
                                }.disabled(model.busy || !model.supported)
                            }
                            Button("목록 새로고침",action:model.refreshFiles).font(.footnote)
                            Text("복원 후 실제 바닥 C를 다시 선택하세요. 화면의 가상 점을 따라 찍지 마세요.").font(.footnote)
                            Button("실제 C 다시 선택 · 오차 검증",action:model.verifyCheckpoint)
                                .disabled(!model.canVerify || model.busy)
                            if let error=model.lastErrorMeters {
                                Text(String(format:"C 오차 %.3fm · 허용 %.2fm",error,model.checkpointTolerance)).font(.caption.monospacedDigit())
                            }
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                    GroupBox("6. 배 착용과 순차 안내") {
                        VStack(alignment:.leading,spacing:10) {
                            Text("배 앞에 세로 고정 · 후면 카메라는 앞쪽, 화면은 몸 쪽. 앱을 전경에 유지하세요. 폰 위치는 발 위치가 아닙니다.").font(.footnote)
                            if let p=model.position {Text(String(format:"폰 X %.2f · Y %.2f · 높이 %.2f m",p.x,p.y,p.z)).monospacedDigit()}
                            else {Text("위치 — · C 검증 필요")}
                            Text(model.heading.map {String(format:"몸 정면 %.1f° · 객석 0°",$0)} ?? "몸 정면 —").monospacedDigit()
                            Button("8초 착용 준비 카운트다운",action:model.startWear)
                                .disabled(!model.ready || model.recordOn || model.wearCountdown != nil)
                            if let count=model.wearCountdown {Text("\(count)초").font(.title.bold())}
                            Text("시작 p0 반경 \(model.settings.startRadius,format:.number.precision(.fractionLength(2)))m · 정면 ±\(model.settings.frontToleranceDegrees,format:.number.precision(.fractionLength(0)))°").font(.caption)
                            Stepper("p0 시작 반경",value:$model.settings.startRadius,in:0.2...1.0,step:0.05).disabled(model.mode != .scanning)
                            Stepper("정면 허용 오차",value:$model.settings.frontToleranceDegrees,in:5...45,step:5).disabled(model.mode != .scanning)
                            Stepper("도착 반경",value:$model.settings.arrivalRadius,in:0.15...1.0,step:0.05).disabled(model.mode != .scanning)
                            Stepper("도착 체류 시간",value:$model.settings.arrivalDwell,in:0.3...3.0,step:0.1).disabled(model.mode != .scanning)
                            Text("도착 반경 \(model.settings.arrivalRadius,format:.number.precision(.fractionLength(2)))m · 체류 \(model.settings.arrivalDwell,format:.number.precision(.fractionLength(1)))초").font(.caption)
                            HStack {
                                Button(model.autoResumePending ? "자동 재개 대기" : (model.guideState == .paused ? "명시적 재개" : "안내 시작"),action:model.startGuide)
                                    .disabled(!model.canGuide || model.autoResumePending)
                                Button("일시정지") {model.pauseGuide()}.disabled(model.guideState != .guiding)
                            }
                            if let target=model.guideTargetIndex, model.routePoints.count >= 2 {
                                Text("현재 목표 p\(target) / 저장된 마지막 p\(model.routePoints.count-1) · \(guideStateLabel)")
                                    .font(.caption.monospacedDigit())
                            }
                            Text(model.guideMessage).font(.headline)
                            if model.autoResumePending {
                                Text(model.heading == nil
                                     ? "후면 카메라 렌즈를 전방으로 향하게 고정하세요. 방향이 안정되면 안내가 이어집니다."
                                     : "무대 안쪽에서 위치가 안정되면 버튼 없이 안내가 이어집니다.").font(.caption)
                            }
                            Text("에어팟 재생/일시정지 명령은 실기기 실험 대상입니다. 화면 버튼을 대안으로 사용하세요.").font(.caption)
                            Button("착용 종료",action:model.stopWear).disabled(!model.recordOn && model.wearCountdown == nil)
                            TextField("실측 위치·회전·조명 메모",text:$model.note).textFieldStyle(.roundedBorder)
                            Button("실측 메모 기록",action:model.addNote).disabled(model.mode == .idle || model.mode == .saved)
                            Button("측정 종료 · 로그 저장",role:.destructive,action:model.endSession)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                    GroupBox("검증 로그 내보내기") {
                        VStack(alignment:.leading,spacing:10) {
                            ForEach(model.exports,id:\.self) {url in
                                ShareLink(item:url) {Label(url.lastPathComponent,systemImage:"square.and.arrow.up").font(.caption).lineLimit(1)}
                            }
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                    }.padding()
                }
            }.navigationTitle("PoC4 Scan Lab").navigationBarTitleDisplayMode(.inline)
                .buttonStyle(.bordered)
                .overlay {if model.busy {ProgressView("처리 중…").padding().background(.regularMaterial,in:RoundedRectangle(cornerRadius:12))}}
                .alert("확인 필요",isPresented:Binding(get:{model.errorMessage != nil},set:{if !$0 {model.errorMessage=nil}})) {
                    Button("확인") {model.errorMessage=nil}
                } message: {Text(model.errorMessage ?? "")}
                .sheet(isPresented:$showPreview) {StagePreviewView(model:model)}
                .onChange(of:scenePhase) {_,phase in model.setActive(phase == .active)}
        }
    }
}
