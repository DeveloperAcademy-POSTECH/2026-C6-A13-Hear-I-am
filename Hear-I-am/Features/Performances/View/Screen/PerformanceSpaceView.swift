import SwiftUI
import HearIAmCore

/// A space is a folder of independently saved scenes, not a mandatory reference-route mapping.
struct PerformanceSpaceView: View {
    @ObservedObject var library: StageLibrary
    let performanceID: UUID
    let venueID: UUID?
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
                    onNewScan:{scanning=true},onStartGuidance:onStartGuidance,
                    onRename:{scanName=record.name;rename=true},onDelete:{deleting=true})
                    .id(record.id)
            } else {
                emptyFolder
                    .navigationTitle("").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement:.principal) {scanSelector}
                        ToolbarItem(placement:.topBarTrailing) {
                            Button("새로고침",systemImage:"arrow.counterclockwise") {Task {await library.refresh()}}
                                .disabled(library.loading)
                        }
                    }
            }
        }.background(HearV3.canvas).foregroundStyle(HearV3.text).tint(HearV3.text)
            .preferredColorScheme(.dark).toolbar(.hidden,for:.tabBar)
            .toolbarBackground(.hidden,for:.navigationBar)
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
            .alert("이 스캔 파일을 삭제할까요?",isPresented:$deleting) {
                Button("취소",role:.cancel) {}
                Button("삭제",role:.destructive) {
                    guard let id=record?.id else {return}
                    perform {try await library.deleteStage(id);selectedScanID=nil}
                }.disabled(working)
            } message: {Text("선택한 장면의 스캔과 사진이 삭제됩니다. 같은 공간의 다른 장면은 유지됩니다.")}
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
            HStack(spacing:10) {
                Image(systemName:"movieclapper")
                Text(record?.name ?? "빈 폴더").lineLimit(1)
                Image(systemName:"chevron.down").font(.caption2.weight(.semibold))
            }.font(.caption.weight(.semibold)).padding(.horizontal,14).frame(minWidth:170,minHeight:44)
                .background(.ultraThinMaterial,in:Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.20),lineWidth:0.5))
        }.accessibilityLabel("\(spaceName), \(record?.name ?? "빈 폴더"), 저장된 장면 선택")
            .accessibilityIdentifier("performance.space.scanPicker")
    }
    private var emptyFolder: some View {
        ZStack {
            HearV3.canvas.ignoresSafeArea()
            VStack(spacing:24) {
                Image(systemName:"viewfinder").font(.system(size:44,weight:.light))
                Text("아직 스캔된\n동선이 없어요").font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                Button {scanning=true} label: {
                    Label("스캔하러 가기",systemImage:"viewfinder")
                        .frame(maxWidth:260)
                }.buttonStyle(V3PrimaryButtonStyle()).frame(maxWidth:260)
                    .accessibilityIdentifier("performance.space.scan")
            }.foregroundStyle(HearV3.secondary).padding(.horizontal,36)
        }.overlay(alignment:.bottom) {
            HStack {
                Button {} label: {Image(systemName:"photo.on.rectangle")}.disabled(true).accessibilityLabel("저장된 사진 없음")
                Spacer()
                Button {} label: {Image(systemName:"timer")}.disabled(true).accessibilityLabel("설정할 경로점 없음")
            }.buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.large)
                .padding(.horizontal,24).padding(.bottom,8)
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
