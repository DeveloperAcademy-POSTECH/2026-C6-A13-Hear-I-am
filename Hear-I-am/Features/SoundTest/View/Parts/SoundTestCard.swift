import SwiftUI

/// One numbered section of the sound test tab: title, what it checks, then its controls.
struct SoundTestCard<Content: View>: View {
    let section: SoundTestSection
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text(section.title).font(.headline)
            Text(section.detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            content
        }.padding(20).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:20))
    }
}

/// A small label above a row of buttons inside a card.
struct SoundTestRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
            LazyVGrid(columns:[GridItem(.adaptive(minimum:132),spacing:8)],alignment:.leading,spacing:8) { content }
        }
    }
}
