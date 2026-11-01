import SwiftUI
import AVFoundation
import HearIAmCore

/// Scan first, then classify the exact saved ID. No scan-ID difference guessing is needed.
struct HelperScanHomeView:View {
    @ObservedObject var library:StageLibrary
    let onShowPerformance:(UUID)->Void
    @State private var scanning=false
    @State private var settings=false
    @State private var cameraDenied=false
    @State private var requestingCamera=false
    @State private var savedID:UUID?
    @State private var classification:SavedScanClassification?
    @State private var openAfterClassification:UUID?
    @State private var refreshFailed=false
    @Environment(\.hearChangeRole) private var changeRole
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    VStack(alignment:.leading,spacing:8) {
                        Text("공연할 공간,\n여기서 준비해요.").font(.title.bold())
                        Text("공간을 담고, 공연에 맞는 무대로 정리해요.").font(.subheadline).foregroundStyle(HearV3.secondary)
                    }
                    VStack(alignment:.leading,spacing:18) {
                        Label("새 무대 스캔",systemImage:"camera").font(.title2.bold())
                        Text("무대와 주변 공간을 천천히 담아주세요.\n공연과 공연장은 스캔을 마친 뒤 정해요.").font(.body).foregroundStyle(HearV3.secondary)
                        Button(requestingCamera ? "카메라 확인 중…" : "새 무대 스캔하기") {startScan()}.buttonStyle(V3PrimaryButtonStyle()).disabled(requestingCamera).accessibilityIdentifier("scan.start")
                    }.v3Card()
                    Text("시작 전, 세 가지만 준비해주세요").font(.subheadline.weight(.semibold)).foregroundStyle(HearV3.secondary)
                    ScanPreparationTip(symbol:"checkmark",title:"밝은 공간",detail:"무대와 기물이 잘 보이게 해주세요.")
                    ScanPreparationTip(symbol:"location",title:"이동할 공간 확보",detail:"무대와 주변 이동 공간을 확인해주세요.")
                    ScanPreparationTip(symbol:"camera",title:"휴대폰은 가로로",detail:"스캔을 시작하면 가로 화면으로 진행해요.")
                    NavigationLink {
                        ScanPreparationHelpView(startScan:startScan)
                    } label:{Text("스캔 방법 자세히 보기").font(.headline).frame(maxWidth:.infinity,minHeight:48).background(HearV3.raised,in:Capsule())}.buttonStyle(.plain)
                    if refreshFailed {
                        VStack(alignment:.leading,spacing:12) {
                            Text("무대는 저장됐지만 목록을 다시 불러와야 해요.").font(.headline)
                            Text("스캔을 다시 하지 않아도 돼요. 저장된 무대를 불러와 분류를 이어가세요.").font(.subheadline).foregroundStyle(HearV3.secondary)
                            Button("저장한 무대 다시 불러오기") {finishScan()}.buttonStyle(.bordered)
                        }.v3Card()
                    }
                }.padding(20)
            }.v3Screen().navigationTitle("스캔").navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.topBarTrailing) {Button {settings=true} label:{Image(systemName:"gearshape")}.accessibilityLabel("설정")}}
        }.v3Screen()
            .navigationDestination(isPresented:$settings) {
                HomeSettingsView(role:.helper,changeRole:changeRole).suspendsVoiceWake()
            }
            .fullScreenCover(isPresented:$scanning,onDismiss:finishScan) {
                PreparationView(library:library,onSaved:{id in savedID=id}).suspendsVoiceWake()
            }
            .sheet(item:$classification,onDismiss:{
                if let id=openAfterClassification {openAfterClassification=nil;onShowPerformance(id)}
            }) {saved in
                StageClassificationView(library:library,scanIDs:[saved.id],wasJustSaved:true,opensPerformanceOnCompletion:true) {id in openAfterClassification=id}.suspendsVoiceWake()
            }
            .alert("카메라 접근이 필요해요",isPresented:$cameraDenied) {
                Button("iPhone 설정 열기") {if let url=URL(string:UIApplication.openSettingsURLString) {UIApplication.shared.open(url)}}
                Button("취소",role:.cancel) {}
            } message:{Text("무대를 스캔하려면 iPhone 설정에서 Hear I am의 카메라 접근을 허용해주세요.")}
    }
    private func startScan() {
        guard !requestingCamera else {return}
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized:savedID=nil;scanning=true
        case .notDetermined:
            requestingCamera=true
            Task {let granted=await AVCaptureDevice.requestAccess(for:.video);requestingCamera=false;if granted {savedID=nil;scanning=true} else {cameraDenied=true}}
        default:cameraDenied=true
        }
    }
    private func finishScan() {
        guard let id=savedID else {return}
        Task {
            await library.refresh()
            if library.records.contains(where:{$0.id==id}) {refreshFailed=false;classification=SavedScanClassification(id:id);savedID=nil}
            else {refreshFailed=true}
        }
    }
}

private struct SavedScanClassification:Identifiable {let id:UUID}

private struct ScanPreparationTip:View {
    let symbol:String
    let title:String
    let detail:String
    var body:some View {
        HStack(alignment:.top,spacing:16) {
            Image(systemName:symbol).font(.title2).frame(width:28).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:6) {Text(title).font(.headline);Text(detail).font(.subheadline).foregroundStyle(HearV3.secondary)}
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

private struct ScanPreparationHelpView:View {
    let startScan:()->Void
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Text("시작하기 전에\n이것만 확인해주세요.").font(.title.bold())
                Text("무대와 그 주변까지 함께 담으면 좋아요.").foregroundStyle(HearV3.secondary)
                ScanPreparationTip(symbol:"camera",title:"천천히, 여러 방향에서",detail:"바닥과 벽, 기물 주변을 고르게 비춰주세요.").v3Card()
                ScanPreparationTip(symbol:"location",title:"무대 밖 이동 공간도 함께",detail:"출입구와 백스테이지 등 이동할 곳을 포함해요.").v3Card()
                ScanPreparationTip(symbol:"photo",title:"필요한 곳은 사진으로 남기기",detail:"여러 위치에서 사진을 남기고 나중에 비교해요.").v3Card()
                VStack(alignment:.leading,spacing:8) {
                    Text("저장할 공연은 나중에 골라도 돼요").font(.headline)
                    Text("스캔과 경로 준비를 마치면 무대를 먼저 저장해요. 그다음 공연 폴더와 공연장 태그로 정리할 수 있어요.").font(.subheadline).foregroundStyle(HearV3.secondary)
                }.v3Card()
            }.padding(20)
        }.v3Screen().navigationTitle("스캔 준비").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge:.bottom) {Button("준비됐어요 · 스캔 시작",action:startScan).buttonStyle(V3PrimaryButtonStyle()).padding(20).background(HearV3.canvas)}
    }
}
