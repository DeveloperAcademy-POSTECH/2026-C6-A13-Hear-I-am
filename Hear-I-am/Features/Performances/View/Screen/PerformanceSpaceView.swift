import SwiftUI
import HearIAmCore

/// A space is a folder of independently saved scenes, not a mandatory reference-route mapping.
struct PerformanceSpaceView: View {
    @ObservedObject var library: StageLibrary
    let performanceID: UUID
    let venueID: UUID?
    /// The scene to show first, when the space is opened from its card on the performance page.
    var initialScanID: UUID? = nil
    let onStartGuidance: (UUID) -> Void
    @State private var selectedScanID: UUID?
    @State private var scanning = false
    @State private var rename = false
    @State private var scanName = ""
    @State private var deleting = false
    @State private var working = false
    @State private var error: String?

    private var records: [ScanManifest] {
        library.scans(in:performanceID,venueID:venueID,includeAllVenues:false)
    }
    private var record: ScanManifest? {records.first {$0.id==selectedScanID} ?? records.first}
    private var spaceName: String {
        library.catalog.performances.first {$0.id==performanceID}?.venues.first {$0.id==venueID}?.name ?? "공간 미분류"
    }
    var body: some View {
        Group {
            if let record {
                ImmersiveSavedStagePreview(record:record,store:library.scans,scanSelector:AnyView(scanSelector),
                    onRename:{scanName=record.name;rename=true},onDelete:{deleting=true})
                    .id(record.id)
            } else {
                // Figma 971:33812: back, the scene picker and refresh over 「아직 스캔된 동선이 없어요」.
                emptyFolder
                    .hearTopBar(center:{scanSelector}) {HearBackButton()} trailing: {
                        ScanCircleButton(systemImage:"arrow.counterclockwise",label:"새로고침",enabled:!library.loading) {
                            Task {await library.refresh()}
                        }
                    }
            }
        }.background(HearV3.canvas).foregroundStyle(HearV3.text).tint(HearV3.text)
            .preferredColorScheme(.dark).toolbar(.hidden,for:.tabBar)
            .toolbarBackground(.hidden,for:.navigationBar)
            .onAppear {if selectedScanID == nil {selectedScanID = initialScanID}}
            .task {await library.refresh()}
            .fullScreenCover(isPresented:$scanning,onDismiss:{Task {await library.refresh()}}) {
                ScanPreparationFlow(library:library,performanceID:performanceID,venueID:venueID) {id in
                    Task {
                        await library.refresh()
                        // A person can classify the new scan into a different folder in the save form.
                        if records.contains(where:{$0.id==id}) {selectedScanID=id}
                    }
                }.suspendsVoiceWake()
            }
            .alert("장면 이름 변경",isPresented:$rename) {
                TextField("무대(장면) 명",text:$scanName)
                Button("취소",role:.cancel) {}
                Button("저장") {
                    guard let id=record?.id else {return}
                    perform {try await library.renameStage(id,to:scanName)}
                }.disabled(scanName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || working)
            }
            // Figma 971:36590: the same confirmation as deleting a folder.
            .hearConfirm("‘\(record?.name ?? "")’ 스캔 파일을 삭제할까요?",isPresented:$deleting,
                         message:"이 장면의 스캔과 사진이 삭제돼요.\n삭제한 내용은 복구할 수 없어요.") {
                guard let id=record?.id,!working else {return}
                perform {try await library.deleteStage(id);selectedScanID=nil}
            }
            .alert("작업을 완료하지 못했어요",isPresented:Binding(get:{error != nil},set:{if !$0 {error=nil}})) {
                Button("확인",role:.cancel) {error=nil}
            } message: {Text(error ?? "")}
            .onDisappear {Task {await library.refresh()}}
    }

    private var scanSelector: some View {
        Menu {
            Section(spaceName) {
                if records.isEmpty {Text("아직 저장된 장면이 없어요")}
                ForEach(records,id:\.id) {scan in
                    Button {
                        selectedScanID=scan.id
                    } label: {
                        if scan.id==record?.id {Label(scan.name,systemImage:"checkmark")}
                        else {Text(scan.name)}
                    }
                }
            }
            Button("새 장면 스캔",systemImage:"viewfinder") {scanning=true}
        } label: {
            // 971:33671: a 170pt glass capsule, the clapper, the scene's name and a chevron in a small disc.
            HStack(spacing:10) {
                Image(systemName:"movieclapper")
                Text(record?.name ?? "빈 폴더").lineLimit(1)
                Image(systemName:"chevron.down.circle.fill").font(.system(size:16)).symbolRenderingMode(.hierarchical)
            }.font(HearFont.pretendard(.medium,size:13)).foregroundStyle(.white).padding(.horizontal,16).frame(minWidth:170,minHeight:44)
                .liquidGlass(Capsule(),tint:ScanChrome.buttonTint,interactive:true)
        }.accessibilityLabel("\(spaceName), \(record?.name ?? "빈 폴더"), 저장된 장면 선택")
            .accessibilityIdentifier("performance.space.scanPicker")
    }
    private var emptyFolder: some View {
        ZStack {
            HearV3.canvas.ignoresSafeArea()
            VStack(spacing:24) {
                Image(systemName:"viewfinder").font(.system(size:44,weight:.light))
                Text("아직 스캔된\n동선이 없어요").font(HearFont.pretendard(.semibold,size:22)).multilineTextAlignment(.center)
                Button {scanning=true} label: {
                    Label("스캔하러 가기",systemImage:"viewfinder")
                        .frame(maxWidth:260)
                }.buttonStyle(V3PrimaryButtonStyle()).frame(maxWidth:260)
                    .accessibilityIdentifier("performance.space.scan")
            }.foregroundStyle(HearV3.secondary).padding(.horizontal,36)
        }.overlay(alignment:.bottom) {
            HStack {
                ScanCircleButton(systemImage:"photo.on.rectangle",label:"저장된 사진 없음",size:48,enabled:false) {}
                Spacer()
                ScanCircleButton(systemImage:"timer",label:"설정할 경로점 없음",size:48,enabled:false) {}
            }.padding(.horizontal,24).padding(.bottom,8)
        }
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !working else {return}
        working=true
        Task {
            defer {working=false}
            do {try await action()} catch {self.error=error.localizedDescription}
        }
    }
}
