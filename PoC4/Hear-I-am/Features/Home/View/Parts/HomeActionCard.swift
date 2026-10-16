import SwiftUI

/// One of the two large entry cards on Home.
struct HomeActionCard: View {
    let title: String
    let subtitle: String
    let image: String
    let dark: Bool
    let action: () -> Void
    var body: some View {
        Button(action:action) {
            VStack(alignment:.leading,spacing:14) {
                Image(image).resizable().scaledToFit().frame(height:86).frame(maxWidth:.infinity).accessibilityHidden(true)
                Spacer(minLength:0)
                HStack(spacing:3) {Text(title).font(.system(size:19,weight:.bold)).minimumScaleFactor(0.8).lineLimit(1); Spacer(minLength:0); Image(systemName:"chevron.right").font(.caption.bold())}
                Text(subtitle).font(.system(size:13)).foregroundStyle(dark ? Color.white.opacity(0.75) : .secondary)
            }.padding(16).frame(maxWidth:.infinity).frame(height:207)
                .foregroundStyle(dark ? .white : .hearInk)
                .background(dark ? Color.hearInk : Color(.systemBackground),in:RoundedRectangle(cornerRadius:22))
                .overlay(RoundedRectangle(cornerRadius:22).stroke(.gray.opacity(dark ? 0 : 0.25)))
        }.buttonStyle(.plain)
    }
}
