import SwiftUI
import HearIAmCore

struct TutorialExampleRow: View {
    let example: SignalTutorialExample
    @ObservedObject var model: SoundTestViewModel
    private var playing: Bool {model.activeID == example.id}
    var body: some View {
        Button {model.play(example)} label: {
            HStack(spacing:12) {
                Image(systemName:example.symbol).font(.system(size:23)).frame(width:38).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:5) {
                    Text(example.title).font(.headline)
                    Text(playing ? "재생 중 · 누르면 중지" : example.detail).font(.subheadline).foregroundStyle(.secondary)
                }.fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                Image(systemName:playing ? "stop.fill" : "play.fill").font(.system(size:15,weight:.semibold))
                    .foregroundStyle(.white).frame(width:40,height:40).background(Color.hearInk,in:Circle()).accessibilityHidden(true)
            }.padding(16).frame(maxWidth:.infinity,minHeight:76,alignment:.leading)
                .background(Color(.systemBackground),in:RoundedRectangle(cornerRadius:18))
                .overlay(RoundedRectangle(cornerRadius:18).stroke(Color(.systemGray5),lineWidth:1))
                .contentShape(RoundedRectangle(cornerRadius:18))
        }.buttonStyle(.plain)
            .accessibilityLabel(example.title+(playing ? " 중지" : " 듣기"))
            .accessibilityValue(playing ? "재생 중" : "")
            .accessibilityHint(example.detail)
            .accessibilityIdentifier("tutorial.preview."+example.id)
    }
}

struct TutorialPlaybackError: View {
    let message: String
    var body: some View {
        Label(message,systemImage:"exclamationmark.circle").font(.subheadline)
            .fixedSize(horizontal:false,vertical:true).padding(14).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:14))
    }
}

struct TutorialOutputLink: View {
    @StateObject private var output=SoundOutputStatus()
    var body: some View {
        NavigationLink {SoundOutputView()} label: {
            HStack(spacing:10) {
                Image(systemName:output.symbol).font(.system(size:20)).accessibilityHidden(true)
                Text("현재 출력 · "+output.name).font(.subheadline).fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:0)
                Image(systemName:"chevron.right").font(.system(size:12)).foregroundStyle(.secondary).accessibilityHidden(true)
            }.padding(14).frame(minHeight:48).background(Color(.systemBackground),in:RoundedRectangle(cornerRadius:14))
                .overlay(RoundedRectangle(cornerRadius:14).stroke(Color(.systemGray5),lineWidth:1))
        }.buttonStyle(.plain).accessibilityHint("소리 출력 설정으로 이동합니다")
            .onAppear {output.refresh()}
    }
}
