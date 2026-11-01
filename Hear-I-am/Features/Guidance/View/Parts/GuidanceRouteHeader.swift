import SwiftUI

/// Compact direction header above the live route camera.
struct GuidanceRouteHeader: View {
    @ObservedObject var model: GuidanceViewModel
    var body: some View {
        let headline=model.headline
        HStack(alignment:.top,spacing:16) {
            Image(systemName:headline.symbol).font(.system(size:42,weight:.medium)).foregroundStyle(model.voiceExperiment ? Color.primary : Color.hearGreen)
                .frame(width:56).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:7) {
                Text(headline.title.replacingOccurrences(of:"\n",with:" ")).font(.title2.bold()).fixedSize(horizontal:false,vertical:true)
                Text(headline.detail).font(model.phase == .guiding ? .title2 : .subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal:false,vertical:true)
            }
            Spacer(minLength:0)
        }.padding(.horizontal,24).padding(.vertical,8)
    }
}
