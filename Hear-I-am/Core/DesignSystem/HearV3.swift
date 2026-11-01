import SwiftUI

/// Shared SEMI tokens from the V3 IA. Kept in the asset catalog for consistent dark surfaces.
enum HearV3 {
    static let canvas=Color("SemiCanvas")
    static let surface=Color("SemiSurface")
    static let raised=Color("SemiRaised")
    static let selected=Color("SemiSelected")
    static let text=Color("SemiText")
    static let secondary=Color("SemiSecondary")
    static let accent=Color(red:0.45,green:0.77,blue:0.64)
}

extension View {
    func v3Card(inset:CGFloat = 20) -> some View {
        padding(inset).frame(maxWidth:.infinity,alignment:.leading)
            .background(HearV3.surface,in:RoundedRectangle(cornerRadius:24,style:.continuous))
    }
    func v3Screen() -> some View {
        background(HearV3.canvas).foregroundStyle(HearV3.text).tint(HearV3.text)
            .preferredColorScheme(.dark)
    }
}

struct V3PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.font(.headline).multilineTextAlignment(.center)
            .frame(maxWidth:.infinity,minHeight:24).padding(.vertical,16).padding(.horizontal,20)
            .foregroundStyle(HearV3.canvas).background(HearV3.text,in:Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
