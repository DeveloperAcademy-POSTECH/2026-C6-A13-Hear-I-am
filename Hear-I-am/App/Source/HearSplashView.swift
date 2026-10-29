import SwiftUI

/// Opening animation from the app icon: the eight rays grow out like stems, then the empty circle at the
/// logo's centre widens, pushing the rays outward, while Home slowly shows inside it and the colours
/// turn into Home's (dark ground to white, white rays to ink). Measured from AppIcon.png (1024 pt, rays 16 pt wide).
struct HearSplashView: View {
    let finish: () -> Void
    @State private var start=Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Grey levels: the icon's ground, Home's white ground and its ink (Color.hearInk).
    private static let darkGround=13.0/255, lightGround=1.0, ink=0.10
    /// Solid parts of each ray as distances from the centre, clockwise from the top.
    private static let rays: [[ClosedRange<Double>]]=[
        [76...302],
        [76...183, 216...250, 279...359],
        [76...302],
        [76...105, 130...363],
        [76...302],
        [76...185, 217...253, 289...370],
        [76...302],
        [76...111, 137...366]
    ]
    private static let hole=76.0
    private static let grow=0.7, stagger=0.05, hold=0.2, open=1.0

    var body: some View {
        TimelineView(.animation) { timeline in
            let t=timeline.date.timeIntervalSince(start)
            Canvas { context,size in draw(&context,size:size,time:t) }
                .opacity(reduceMotion ? 1-min(1,t/0.4) : 1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            let total=reduceMotion ? 0.4 : Self.grow+Self.stagger*7+Self.hold+Self.open
            try? await Task.sleep(nanoseconds:UInt64(total*1_000_000_000))
            finish()
        }
    }

    private var growEnd: Double {Self.grow+Self.stagger*7}

    private func draw(_ context: inout GraphicsContext, size: CGSize, time t: Double) {
        let center=CGPoint(x:size.width/2,y:size.height/2)
        let unit=min(size.width,size.height)*0.8/1024
        let opening=reduceMotion ? 0 : ease(min(1,max(0,(t-growEnd-Self.hold)/Self.open)))
        let ground=Self.darkGround+(Self.lightGround-Self.darkGround)*opening
        let ray=1+(Self.ink-1)*opening
        // The logo's own centre circle widens to beyond the screen corners.
        let far=hypot(size.width,size.height)/2+16
        let hole=Self.hole*unit+(far-Self.hole*unit)*opening
        let circle=Path(ellipseIn:CGRect(x:center.x-hole,y:center.y-hole,width:hole*2,height:hole*2))
        var outside=Path(CGRect(origin:.zero,size:size));outside.addPath(circle)
        context.fill(outside,with:.color(Color(white:ground)),style:FillStyle(eoFill:true))
        // Inside it Home shows through a little more as it grows; before opening it is the icon's dark centre.
        context.fill(circle,with:.color(Color(white:ground).opacity(1-opening)))
        let shift=hole-Self.hole*unit

        for (index,segments) in Self.rays.enumerated() {
            let grown=reduceMotion ? 1 : ease(min(1,max(0,(t-Double(index)*Self.stagger)/Self.grow)))
            let reach=Self.hole+(segments.last!.upperBound-Self.hole)*grown
            let angle=Double(index) * .pi/4
            let direction=CGVector(dx:sin(angle),dy:-cos(angle))
            var path=Path()
            for segment in segments where segment.lowerBound < reach {
                let from=segment.lowerBound*unit+shift, to=min(segment.upperBound,reach)*unit+shift
                path.move(to:CGPoint(x:center.x+direction.dx*from,y:center.y+direction.dy*from))
                path.addLine(to:CGPoint(x:center.x+direction.dx*to,y:center.y+direction.dy*to))
            }
            context.stroke(path,with:.color(Color(white:ray).opacity(1-opening*opening)),style:StrokeStyle(lineWidth:16*unit,lineCap:.butt))
        }
    }

    private func ease(_ x: Double) -> Double {x < 0.5 ? 4*x*x*x : 1-pow(-2*x+2,3)/2}
}
