import SwiftUI
import HearIAmCore

/// The scan tab's start page (Figma 971:28135): the way back to the role page at the top left, and in the middle
/// the viewfinder, 「무대 준비를 위한 스캔을 시작해보세요」 and 「스캔하러 가기」. The scan begins with the stage information page (ScanPreparationFlow).
struct HelperScanHomeView:View {
    @ObservedObject var library:StageLibrary
    /// Set when the performer asked for a scan by voice: the scan itself opens, not this tab's start page (11/03).
    @Binding var startNow:Bool
    let onShowPerformance:(UUID)->Void
    @State private var scanning=false
    @State private var showingSettings=false
    @Environment(\.hearChangeRole) private var changeRole
    var body:some View {
        NavigationStack {
            page.navigationDestination(isPresented:$scanning) {flow}
                .navigationDestination(isPresented:$showingSettings) {HomeSettingsView()}
        }
    }
    /// The stage information page slides in from the side like any other page, not up from the bottom (11/07).
    private var flow:some View {
        ScanPreparationFlow(library:library) {id in
            if let performanceID=library.catalog.assignments[id]?.performanceID {
                onShowPerformance(performanceID)
            }
        }.suspendsVoiceWake()
    }
    private var page:some View {
        VStack(spacing:0) {
            Image(systemName:"viewfinder").font(.system(size:40)).foregroundStyle(ScanHomeStyle.text)
                .frame(height:40).accessibilityHidden(true)
            Text("무대 준비를 위한\n스캔을 시작해보세요").font(HearFont.pretendard(.semibold,size:22))
                .foregroundStyle(ScanHomeStyle.text).multilineTextAlignment(.center).padding(.top,25)
            Button {startScan()} label: {
                HStack(spacing:8) {
                    Image(systemName:"viewfinder").font(.system(size:18,weight:.semibold))
                    Text("스캔하러 가기").font(HearFont.pretendard(.semibold,size:18))
                }.foregroundStyle(ScanHomeStyle.buttonText).frame(width:258,height:50)
                    .liquidGlass(Capsule(),tint:.white,interactive:true).contentShape(Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("scan.start").padding(.top,44)
        }.offset(y:ScanHomeStyle.groupOffset)
            // Centred on the whole screen, not the safe area: the tab bar hides while the information page is pushed
            // and comes back on the way out, which would otherwise move the button as the safe area changes (11/07).
            .frame(maxWidth:.infinity,maxHeight:.infinity).ignoresSafeArea()
            .v3Screen()
            // Home and settings in the shared top row, where the role page keeps its settings button (11/07).
            .hearTopBar(nil) {
                Button {changeRole?()} label: {HearTopButtonLabel(systemImage:"house")}
                    .buttonStyle(.plain).accessibilityLabel("역할 선택으로 돌아가기")
            } trailing: {
                Button {showingSettings=true} label: {HearTopButtonLabel(systemImage:"gearshape")}
                    .buttonStyle(.plain).accessibilityLabel("설정").accessibilityIdentifier("scan.settings")
            }
            .onAppear {startRequestedScan()}
            .onChange(of:startNow) {startRequestedScan()}
    }
    private func startRequestedScan() {
        guard startNow else {return}
        startNow=false
        startScan()
    }
    private func startScan() { scanning=true }
}

private enum ScanHomeStyle {
    static let buttonText=Color(red:38/255,green:38/255,blue:38/255)
    static let text=Color(red:250/255,green:250/255,blue:250/255)
    /// Figma 971:28135 runs the group from 320 to 531 of 874: its middle 11.5pt above the screen's.
    static let groupOffset:CGFloat = -11.5
}
