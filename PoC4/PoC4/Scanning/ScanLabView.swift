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
    @State private var showPreview = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Text("1단계 · 스캔과 위치 복원").font(.title2.bold())
                    Text("실험용 위치 기록 · 경로 안내와 물체 감지는 아직 제공하지 않습니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ZStack {
                        CameraView(model:model)
                        Image(systemName:"plus").font(.title).foregroundStyle(.white)
                            .shadow(color:.black,radius:2).accessibilityHidden(true)
                        VStack { Spacer(); Text("십자선 중심을 실제 바닥 표식에 맞추세요")
                            .font(.caption).padding(6).background(.black.opacity(0.65)).foregroundStyle(.white) }
                    }.frame(height:280).clipShape(RoundedRectangle(cornerRadius:12))
                    Button { showPreview = true } label: {
                        Label("스캔 공간 3D 보기", systemImage: "cube.transparent")
                    }.disabled(model.meshCount == 0)
                    Text("수집된 형상을 회전·확대해 확인합니다. 스캔 중에도 갱신됩니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !model.supported {
                        Label("이 기기는 LiDAR 메시 스캔을 지원하지 않습니다. 시뮬레이터에서는 화면만 확인할 수 있습니다.",systemImage:"info.circle")
                            .foregroundStyle(.orange)
                    }
                    Text(model.status).font(.headline).accessibilityIdentifier("lab-status")
                    HStack { Text("추적: \(model.tracking)"); Spacer(); Text("지도: \(model.mapping)") }.font(.caption)
                    Text("메시 \(model.meshCount)개 · 정점 \(model.vertexCount)개").font(.caption.monospacedDigit())
                    Toggle("메시 표시 · 새 스캔 초록 / 저장 공간 주황",isOn:$model.showMesh).font(.footnote)
                    GroupBox("1. 무대 스캔") {
                        VStack(alignment:.leading,spacing:12) {
                            TextField("스캔 이름",text:$model.scanName).textFieldStyle(.roundedBorder)
                            Button("새 스캔 시작",action:model.newScan).disabled(!model.supported || model.busy)
                            Text("바닥에 O(원점), F(객석 방향), C(별도 확인점)를 표시합니다. 각 점은 0.5m 이상 떨어지게 하세요. K1~K4 도면 정합은 이후 단계입니다.")
                                .font(.footnote)
                            HStack {
                                Button("O 선택") {model.capture("O")}
                                Button("F 선택") {model.capture("F")}
                                Button("C 선택") {model.capture("C")}
                            }.disabled(model.mode != .scanning || model.busy)
                            Text(model.references).font(.caption)
                            Button("메시와 공간 지도 저장",action:model.save).disabled(!model.canSave || model.busy)
                            Text("카메라가 mapped 상태이고 O·F·C와 메시가 있어야 저장됩니다.").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                    GroupBox("2. 저장 공간 복원") {
                        VStack(alignment:.leading,spacing:10) {
                            if model.records.isEmpty { Text("저장된 스캔이 없습니다.").foregroundStyle(.secondary) }
                            ForEach(model.records,id:\.id) { item in
                                Button {model.restore(item)} label: {
                                    VStack(alignment:.leading) {
                                        Text(item.name).font(.headline)
                                        Text("\(item.date.formatted()) · 메시 \(item.meshCount)").font(.caption)
                                    }
                                }.disabled(model.busy || !model.supported)
                            }
                            Button("목록 새로고침",action:model.refreshFiles).font(.footnote)
                            Text("복원 후 실제 C에 십자선을 맞추고 검증하세요. 화면의 가상 C를 따라 찍지 말고 바닥의 실제 표식을 확인하세요.").font(.footnote)
                            Button("실제 C 다시 선택 · 오차 검증",action:model.verifyCheckpoint)
                                .disabled(!model.canVerify || model.busy)
                            if let error=model.lastErrorMeters {
                                Text(String(format:"C 오차 %.3fm · 실험 허용값 %.2fm",error,model.checkpointTolerance)).font(.caption.monospacedDigit())
                            }
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                    GroupBox("3. 착용 위치 · 방향 기록") {
                        VStack(alignment:.leading,spacing:10) {
                            Text("배 앞에 세로 고정 · 후면 카메라는 앞쪽, 화면은 몸 쪽. 시작 버튼 후 8초 동안 고정하세요. 폰이 밴드에서 돌아가지 않게 고정합니다.").font(.footnote)
                            if let p=model.position {
                                Text(String(format:"X %.2f · Y %.2f · 높이 %.2f m",p.x,p.y,p.z)).monospacedDigit()
                            } else { Text("위치 — · 기준점 검증 또는 추적 확인 필요") }
                            Text(model.heading.map {String(format:"몸 정면 %.1f° · 객석 0°",$0)} ?? "몸 정면 —")
                                .monospacedDigit()
                            HStack {
                                Button("8초 후 착용 기록 시작",action:model.startWear).disabled(!model.ready || model.recordOn || model.wearCountdown != nil)
                                Button("구간 종료",action:model.stopWear).disabled(!model.recordOn && model.wearCountdown == nil)
                            }
                            Text(model.recordOn ? "● 착용 구간 기록 중" : "관측 로그는 세션 시작부터 자동 기록").font(.caption)
                            TextField("실측 위치·회전 각도·조명·메모",text:$model.note).textFieldStyle(.roundedBorder)
                            Button("실측 메모 기록",action:model.addNote).disabled(model.mode == .idle || model.mode == .saved)
                            Button("측정 종료 · 로그 저장",role:.destructive,action:model.endSession)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                    GroupBox("검증 로그 내보내기") {
                        VStack(alignment:.leading,spacing:10) {
                            Text("JSONL: 추정 좌표·방향, 품질 상태, C 검증, 착용 구간, 실측 메모. 종료 후 공유하세요. 중단된 로그도 파일 앱에서 복구할 수 있습니다.").font(.footnote)
                            ForEach(model.exports,id:\.self) { url in
                                ShareLink(item:url) {Label(url.lastPathComponent,systemImage:"square.and.arrow.up").font(.caption).lineLimit(1)}
                            }
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    }
                }.padding()
            }.navigationTitle("PoC4 Scan Lab").navigationBarTitleDisplayMode(.inline)
                .buttonStyle(.bordered)
                .overlay {if model.busy {ProgressView("처리 중…").padding().background(.regularMaterial,in:RoundedRectangle(cornerRadius:12))}}
                .alert("확인 필요",isPresented:Binding(get:{model.errorMessage != nil},set:{if !$0 {model.errorMessage=nil}})) {
                    Button("확인") {model.errorMessage=nil}
                } message: {Text(model.errorMessage ?? "")}
                .sheet(isPresented: $showPreview) {
                    StagePreviewView(model: model)
                }
                .onChange(of:scenePhase) { _,phase in model.setActive(phase == .active) }
                .accessibilityAction(.magicTap) {model.endSession()}
        }
    }
}
