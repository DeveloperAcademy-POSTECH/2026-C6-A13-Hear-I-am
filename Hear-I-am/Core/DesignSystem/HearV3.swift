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
            // Content scrolling up must not show through the status bar or between the buttons: the page colour
            // stays solid down to the buttons' middle and fades out a little below the row. Over a stage (a control
            // in the middle) only a light shade, so the scene still reaches the top.
            .background {
                if !sheet {
                    if center == nil {
                        LinearGradient(stops:[.init(color:HearV3.canvas,location:0),.init(color:HearV3.canvas,location:0.62),
                                              .init(color:HearV3.canvas.opacity(0),location:1)],startPoint:.top,endPoint:.bottom)
                            .padding(.bottom,-22).ignoresSafeArea(edges:.top).allowsHitTesting(false)
                    } else {
                        LinearGradient(colors:[.black,.black.opacity(0)],startPoint:.top,endPoint:.bottom).ignoresSafeArea(edges:.top)
                    }
                }
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

// MARK: - Confirmation

/// The delete confirmation (Figma 971:36590) in the app's own colours: a dark glass card, the title and message on
/// the left, 취소 on grey and the action in white with black text. It fades in over everything, tab bar included.
struct HearConfirmAlert: View {
    let title: String
    let message: String
    let confirm: String
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @State private var shown=false
    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.45 : 0).ignoresSafeArea().onTapGesture {}
            VStack(alignment:.leading,spacing:0) {
                Text(title).font(.system(size:17,weight:.semibold)).foregroundStyle(.white).fixedSize(horizontal:false,vertical:true)
                    .accessibilityAddTraits(.isHeader)
                Text(message).font(.system(size:15)).foregroundStyle(.white.opacity(0.7)).lineSpacing(2)
                    .fixedSize(horizontal:false,vertical:true).padding(.top,8)
                HStack(spacing:8) {
                    Button {close(onCancel)} label: {
                        Text("취소").font(.system(size:17,weight:.medium)).foregroundStyle(.white)
                            .frame(maxWidth:.infinity).frame(height:48).background(.white.opacity(0.14),in:Capsule())
                    }.buttonStyle(.plain)
                    Button {close(onConfirm)} label: {
                        Text(confirm).font(.system(size:17,weight:.semibold)).foregroundStyle(.black)
                            .frame(maxWidth:.infinity).frame(height:48).background(.white,in:Capsule())
                    }.buttonStyle(.plain)
                }.padding(.top,20)
            }.padding(.horizontal,22).padding(.top,22).padding(.bottom,14).frame(width:300)
                .background(Color(white:0.13).opacity(0.92),in:RoundedRectangle(cornerRadius:34,style:.continuous))
                .liquidGlass(RoundedRectangle(cornerRadius:34,style:.continuous))
                .scaleEffect(shown ? 1 : 1.08).opacity(shown ? 1 : 0)
                .accessibilityElement(children:.contain).accessibilityAddTraits(.isModal)
        }.onAppear {withAnimation(.spring(duration:0.28)) {shown=true}}
    }
    private func close(_ then: @escaping () -> Void) {
        withAnimation(.easeOut(duration:0.16)) {shown=false}
        DispatchQueue.main.asyncAfter(deadline:.now()+0.17,execute:then)
    }
}

extension View {
    /// Shows `HearConfirmAlert` while `isPresented` is true. The cover itself appears without sliding up; the card
    /// does its own fade.
    func hearConfirm(_ title: String, isPresented: Binding<Bool>, message: String, confirm: String="삭제",
                     action: @escaping () -> Void) -> some View {
        fullScreenCover(isPresented:isPresented) {
            HearConfirmAlert(title:title,message:message,confirm:confirm,onCancel:{isPresented.wrappedValue=false},
                             onConfirm:{isPresented.wrappedValue=false;action()})
                .presentationBackground(.clear)
        }.transaction(value:isPresented.wrappedValue) {$0.disablesAnimations=true}
    }
}

// MARK: - Swipe to delete

/// A list row that slides left to show a delete button, as in Mail; a long swipe asks straight away. Tapping the
/// row opens it, or closes the button when it is showing.
struct HearSwipeDeleteRow<Content: View>: View {
    let onOpen: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: Content
    @State private var offset: CGFloat=0
    @State private var start: CGFloat?
    @State private var horizontal: Bool?
    private let reveal: CGFloat=78
    var body: some View {
        ZStack(alignment:.trailing) {
            Button {settle(0);onDelete()} label: {
                Image(systemName:"trash").font(.system(size:18,weight:.semibold)).foregroundStyle(.black)
                    .frame(width:56,height:56).background(.white,in:Circle())
            }.buttonStyle(.plain).frame(width:reveal).opacity(min(1,-offset/reveal)).scaleEffect(0.6+0.4*min(1,-offset/reveal))
                .accessibilityHidden(true)
            content.offset(x:offset).contentShape(Rectangle())
                .onTapGesture {if offset != 0 {settle(0)} else {onOpen()}}
                .simultaneousGesture(DragGesture(minimumDistance:12).onChanged {value in
                    if horizontal == nil {horizontal=abs(value.translation.width)>abs(value.translation.height)}
                    guard horizontal == true else {return}
                    if start == nil {start=offset}
                    let raw=(start ?? 0)+value.translation.width
                    offset=raw>0 ? raw*0.15 : raw
                }.onEnded {value in
                    defer {horizontal=nil;start=nil}
                    guard horizontal == true else {return}
                    let end=(start ?? 0)+value.predictedEndTranslation.width
                    if end < -260 {settle(0);onDelete()}
                    else {settle(end < -reveal/2 ? -reveal : 0)}
                })
        }.accessibilityElement(children:.combine).accessibilityAddTraits(.isButton)
            .accessibilityAction {onOpen()}
            .accessibilityAction(named:"삭제",onDelete)
    }
    private func settle(_ value: CGFloat) {withAnimation(.spring(duration:0.3,bounce:0.15)) {offset=value}}
}
