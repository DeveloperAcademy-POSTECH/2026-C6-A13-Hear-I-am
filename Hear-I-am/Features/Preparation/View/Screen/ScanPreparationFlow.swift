import SwiftUI
import AVFoundation
import HearIAmCore

/// One owner for pre-scan choices, the camera cover, and the already-saved scan's classification.
/// Pushed onto the scan tab's navigation stack, so it has no stack of its own.
struct ScanPreparationFlow: View {
    @ObservedObject var library: StageLibrary
    let onSaved: (UUID) -> Void
    @State private var performanceID: UUID?
    @State private var venueID: UUID?
    @State private var sceneName = ""
    @State private var scanning = false
    @State private var requestingCamera = false
    @State private var cameraDenied = false
    @State private var savedID: UUID?
    @State private var postScan = false
    @State private var busy = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(library: StageLibrary, performanceID: UUID? = nil, venueID: UUID? = nil, onSaved: @escaping (UUID) -> Void) {
        self.library = library; self.onSaved = onSaved
        // Every new scan begins unclassified, including entry from an existing space folder.
        _performanceID = State(initialValue: nil); _venueID = State(initialValue: nil)
    }
    var body: some View {
        Group {
            if postScan, let savedID {
                StageClassificationView(library: library, scanIDs: [savedID], initialPerformanceID: performanceID,
                    initialVenueID: venueID, wasJustSaved: true, embedded: true) { _ in
                        onSaved(savedID); dismiss()
                    }
            } else {
                ScrollView {
                    // Figma 971:22703: the title, then the three fields 32.6pt under it.
                    VStack(alignment: .leading, spacing: 0) {
                        StageInfoTitle(text: "스캔할 무대의\n정보를 입력해주세요")
                        StageInformationFields(library: library, stageName: $sceneName, performanceID: $performanceID, venueID: $venueID)
                            .disabled(busy || requestingCamera).padding(.top, 32.6)
                        if let error {
                            Text(error).font(.callout).foregroundStyle(.red).padding(.top, 16)
                            if savedID != nil { Button("저장한 무대 다시 불러오기") { finishScan() }.padding(.top, 8) }
                        }
                    }.padding(.horizontal, 16).padding(.top, StageInfoStyle.titleTop).padding(.bottom, 24)
                }.v3Screen().navigationTitle("무대 저장")
                    .hearTopBar("무대 저장") {
                        HearBackButton(enabled: !(busy || requestingCamera))
                    } trailing: {
                        Menu { Button("입력 내용 초기화") { sceneName = ""; performanceID = nil; venueID = nil } } label: { HearTopButtonLabel(systemImage: "ellipsis") }
                            .disabled(busy || requestingCamera).accessibilityLabel("더보기")
                    }
                    .stageInfoBottomBar(height: 120) {
                        VStack(spacing: 8) {
                            StageInfoButton(title: "건너뛰기", primary: false) { sceneName = ""; performanceID = nil; venueID = nil; beginScan() }
                                .disabled(requestingCamera || busy || savedID != nil)
                            StageInfoButton(title: busy ? "무대를 불러오는 중…" : requestingCamera ? "카메라 확인 중…" : "저장 후 스캔하기", primary: true, action: beginScan)
                                .disabled(requestingCamera || busy || sceneName.count > 80 || savedID != nil)
                                .accessibilityIdentifier("scan.beginWithInformation")
                        }.padding(.horizontal, 16)
                    }
            }
        }.v3Screen()
            // Pushed from the scan tab (it slides in from the side); the tab bar stays out of the way as in 971:22703.
            .toolbar(.hidden, for: .tabBar)
            .task { await library.refresh() }
            .scanCover(isPresented: $scanning, onDismiss: finishScan) {
                PreparationView(library: library, performanceID: performanceID, sceneName: sceneName) { savedID = $0 }.suspendsVoiceWake()
            }
            .alert("카메라 접근이 필요해요", isPresented: $cameraDenied) {
                Button("iPhone 설정 열기") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                Button("취소", role: .cancel) {}
            } message: { Text("무대를 스캔하려면 iPhone 설정에서 카메라 접근을 허용해주세요.") }
    }
    private func beginScan() {
        guard !requestingCamera, !busy, savedID == nil else { return }
        error = nil
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: scanning = true
        case .notDetermined:
            requestingCamera = true
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                requestingCamera = false
                if granted { scanning = true } else { cameraDenied = true }
            }
        default: cameraDenied = true
        }
    }
    private func finishScan() {
        guard let savedID, !busy else { return }; busy = true; error = nil
        Task {
            await library.refresh()
            guard library.records.contains(where: { $0.id == savedID }) else {
                error = "무대는 저장됐지만 목록을 불러오지 못했어요. 스캔을 다시 하지 않고 불러오기를 재시도할 수 있어요."
                busy = false; return
            }
            do {
                // Preserve preselected destination even if the user closes the post-scan form.
                try await library.assignScans([savedID], to: performanceID, venueID: venueID)
                postScan = true
            } catch { self.error = "무대는 저장됐어요. 저장 위치 연결을 다시 시도해주세요. \(error.localizedDescription)" }
            busy = false
        }
    }
}
