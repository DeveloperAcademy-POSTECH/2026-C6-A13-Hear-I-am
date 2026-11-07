import SwiftUI

/// Shared SEMI tokens from the V3 IA. Kept in the asset catalog for consistent dark surfaces.
enum HearV3 {
    static let canvas=Color("SemiCanvas")
    static let surface=Color("SemiSurface")
    static let raised=Color("SemiRaised")
    static let selected=Color("SemiSelected")
    static let text=Color("SemiText")
    static let secondary=Color("SemiSecondary")
    static let accent=Color(red:114.0/255,green:201.0/255,blue:155.0/255)
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
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.font(.headline).multilineTextAlignment(.center)
            .frame(maxWidth:.infinity,minHeight:24).padding(.vertical,16).padding(.horizontal,20)
            .foregroundStyle(HearV3.canvas).background(HearV3.text,in:Capsule())
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    /// Liquid Glass on iOS 26 (the design's 「Liquid Glass - Regular」 fills); a thin material in the same shape before that.
    @ViewBuilder func liquidGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            let glass: Glass = tint.map {Glass.regular.tint($0)} ?? .regular
            self.glassEffect(interactive ? glass.interactive() : glass, in: shape)
        } else {
            self.background(tint ?? .clear, in: shape).background(.ultraThinMaterial, in: shape)
        }
    }
}

// MARK: - The one top row

/// The top row of every portrait page (11/07): 44pt round buttons 14pt under the status bar and 18pt in from
/// the sides, where the role page keeps its settings button, with the title centred between them. Pages use it
/// through `hearTopBar` instead of the navigation bar, which would sit 14pt higher.
struct HearTopBar<Leading: View, Trailing: View>: View {
    let title: String?
    /// A control in the title's place, such as the scene picker on a space page.
    var center: AnyView?=nil
    /// On a sheet the row sits 25pt under the sheet's top edge, below the grabber, on the sheet's own glass.
    var sheet=false
    let leading: Leading
    let trailing: Trailing
    var body: some View {
        HStack(spacing:8) {
            HStack(spacing:8) {leading}
            Spacer(minLength:8)
            HStack(spacing:8) {trailing}
        }.frame(height:44)
            .overlay {
                if let center {center}
                else if let title {
                    Text(title).font(.headline).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
                        .readAloudTarget(title).padding(.horizontal,60).accessibilityAddTraits(.isHeader)
                }
            }
            .padding(.horizontal,18).padding(.top,sheet ? 25 : 14).padding(.bottom,8)
            // Content scrolling up fades out under the buttons, as it did under the system bar.
            .background {
                if !sheet {LinearGradient(colors:[.black,.black.opacity(0)],startPoint:.top,endPoint:.bottom).ignoresSafeArea(edges:.top)}
            }
    }
}

/// A 44pt round top-row button face: dark glass, or white with a black symbol for the page's main action.
struct HearTopButtonLabel: View {
    let systemImage: String
    var prominent=false
    var body: some View {
        if prominent {
            Image(systemName:systemImage).font(.system(size:17,weight:.semibold)).foregroundStyle(.black)
                .frame(width:44,height:44).liquidGlass(Circle(),tint:.white,interactive:true).contentShape(Circle())
        } else {
            ScanCircleLabel(systemImage:systemImage)
        }
    }
}

/// The top row's back button: closes the page it sits on.
struct HearBackButton: View {
    var enabled=true
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button {dismiss()} label: {HearTopButtonLabel(systemImage:"chevron.left")}
            .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.45)
            .accessibilityLabel("뒤로").accessibilityIdentifier("top.back")
    }
}

extension View {
    /// Puts `HearTopBar` over the page in place of the navigation bar.
    func hearTopBar<Leading: View, Trailing: View>(_ title: String?, sheet: Bool=false, @ViewBuilder leading: () -> Leading,
                                                    @ViewBuilder trailing: () -> Trailing) -> some View {
        toolbar(.hidden,for:.navigationBar)
            .safeAreaInset(edge:.top,spacing:0) {HearTopBar(title:title,sheet:sheet,leading:leading(),trailing:trailing())}
    }
    /// Lets a navigation stack inside a sheet show the sheet's own surface (iOS 18 and later).
    @ViewBuilder func clearNavigationBackground() -> some View {
        if #available(iOS 18, *) {containerBackground(.clear,for:.navigation)} else {self}
    }
    /// A page shown as a sheet (Figma 971:32062): it must read as a layer over the page, not as another page. The
    /// sheet keeps its 42pt corners, grabber and a lit rim on the dark glass, and its content paints no background.
    func hearSheet(_ detents: Set<PresentationDetent> = [.large]) -> some View {
        foregroundStyle(HearV3.text).tint(HearV3.text).scrollContentBackground(.hidden)
            .clearNavigationBackground()
            .presentationDetents(detents).presentationDragIndicator(.visible)
            .presentationCornerRadius(42).presentationBackground {HearSheetBackground()}
            .preferredColorScheme(.dark)
    }
    /// The same row with a control in the middle instead of a title.
    func hearTopBar<Center: View, Leading: View, Trailing: View>(@ViewBuilder center: () -> Center, @ViewBuilder leading: () -> Leading,
                                                                  @ViewBuilder trailing: () -> Trailing) -> some View {
        toolbar(.hidden,for:.navigationBar)
            .safeAreaInset(edge:.top,spacing:0) {HearTopBar(title:nil,center:AnyView(center()),leading:leading(),trailing:trailing())}
    }
}

/// The sheet surface: near-black glass a step lighter than the page, brightening toward the lower right, with the
/// light catching its top-left rim.
struct HearSheetBackground: View {
    var body: some View {
        LinearGradient(colors:[Color(white:0.075),Color(white:0.13)],startPoint:.topLeading,endPoint:.bottomTrailing)
            .overlay {
                RoundedRectangle(cornerRadius:42,style:.continuous)
                    .strokeBorder(LinearGradient(colors:[.white.opacity(0.32),.white.opacity(0.05),.white.opacity(0.12)],
                                                 startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1)
            }.ignoresSafeArea()
    }
}
