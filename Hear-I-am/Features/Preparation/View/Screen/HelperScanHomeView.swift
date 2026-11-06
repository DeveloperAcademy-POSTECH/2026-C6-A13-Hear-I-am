import SwiftUI
import AVFoundation
import HearIAmCore

/// Scan first, then classify the exact saved ID. No scan-ID difference guessing is needed.
struct HelperScanHomeView:View {
    @ObservedObject var library:StageLibrary
    /// Set when the performer asked for a scan by voice: the scan itself opens, not this tab's start page (11/03).
    @Binding var startNow:Bool
    let onShowPerformance:(UUID)->Void
    @State private var scanning=false
    @State private var settings=false
    @Environment(\.hearChangeRole) private var changeRole
    var body:some View {
        NavigationStack {
            ScrollView {
                // Figma 245:3178 mood in black: eyebrow, two-line headline, the stage illustration, three steps, one button.
                VStack(alignment:.leading,spacing:0) {
                    // Title and the settings button share one row (Figma 245:3178); the bar itself is hidden.
                    HStack(alignment:.center) {
                        Text("스캔").font(.system(size:34,weight:.bold))
                        Spacer()
                        Button {settings=true} label:{
                            Image(systemName:"gearshape").font(.system(size:17,weight:.semibold))
                                .frame(width:44,height:44).liquidGlass(Circle(),interactive:true)
                        }.buttonStyle(.plain).accessibilityLabel("설정")
                    }.padding(.bottom,28)
                    Text("무대 준비").font(.system(size:13,weight:.semibold)).foregroundStyle(HearV3.accent).padding(.bottom,10)
                    Text("공연할 공간을\n담아보세요.").font(.system(size:34,weight:.bold)).lineSpacing(2).padding(.bottom,12)
                    Text("바닥과 벽, 무대 주변을 천천히 비춰주세요.").font(.system(size:15)).foregroundStyle(HearV3.secondary).padding(.bottom,28)
                    ScanStageIllustration().frame(height:240).frame(maxWidth:.infinity)
                        .background(HearV3.surface,in:RoundedRectangle(cornerRadius:24,style:.continuous))
                        .accessibilityHidden(true).padding(.bottom,24)
                    ScanStepsRow().padding(.horizontal,4).padding(.bottom,28)
                    Button {startScan()} label: {
                        Label("스캔 시작하기",systemImage:"viewfinder")
                    }.buttonStyle(V3PrimaryButtonStyle()).accessibilityIdentifier("scan.start")
                    Text("충분한 밝기와 이동할 공간을 확인해주세요.").font(.system(size:13)).foregroundStyle(HearV3.secondary)
                        .frame(maxWidth:.infinity).padding(.top,14)
                    NavigationLink {
                        ScanPreparationHelpView(startScan:startScan)
                    } label:{
                        Text("스캔 방법 자세히 보기").font(.system(size:15,weight:.semibold)).underline()
                            .frame(maxWidth:.infinity,minHeight:44)
                    }.buttonStyle(.plain).padding(.top,6)
                }.padding(.horizontal,20).padding(.top,12).padding(.bottom,24)
            }.v3Screen().navigationTitle("스캔").toolbar(.hidden,for:.navigationBar)
                // The destination must sit inside the stack; outside it the button does nothing.
                .navigationDestination(isPresented:$settings) {
                    HomeSettingsView().suspendsVoiceWake()
                }
        }.v3Screen()
            .onAppear {startRequestedScan()}
            .onChange(of:startNow) {startRequestedScan()}
            .fullScreenCover(isPresented:$scanning) {
                ScanPreparationFlow(library:library) {id in
                    if let performanceID=library.catalog.assignments[id]?.performanceID {
                        onShowPerformance(performanceID)
                    }
                }.suspendsVoiceWake()
            }
    }
    private func startRequestedScan() {
        guard startNow else {return}
        startNow=false
        startScan()
    }
    private func startScan() { scanning=true }
}

private struct ScanPreparationTip:View {
    let symbol:String
    let title:String
    let detail:String
    var body:some View {
        HStack(alignment:.top,spacing:16) {
            Image(systemName:symbol).font(.title2).frame(width:28).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:6) {Text(title).font(.headline);Text(detail).font(.subheadline).foregroundStyle(HearV3.secondary)}
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

private struct ScanPreparationHelpView:View {
    let startScan:()->Void
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Text("시작하기 전에\n이것만 확인해주세요.").font(.title.bold())
                Text("무대와 그 주변까지 함께 담으면 좋아요.").foregroundStyle(HearV3.secondary)
                ScanPreparationTip(symbol:"camera",title:"천천히, 여러 방향에서",detail:"바닥과 벽, 기물 주변을 고르게 비춰주세요.").v3Card()
                ScanPreparationTip(symbol:"location",title:"무대 밖 이동 공간도 함께",detail:"출입구와 백스테이지 등 이동할 곳을 포함해요.").v3Card()
                ScanPreparationTip(symbol:"photo",title:"필요한 곳은 사진으로 남기기",detail:"여러 위치에서 사진을 남기고 나중에 비교해요.").v3Card()
                VStack(alignment:.leading,spacing:8) {
                    Text("저장할 공연은 나중에 골라도 돼요").font(.headline)
                    Text("스캔 전이나 후에 공연과 연습 공간을 선택할 수 있어요. 공연을 먼저 고르면 그 공연의 씬 동선을 참고할 수 있어요.").font(.subheadline).foregroundStyle(HearV3.secondary)
                }.v3Card()
            }.padding(20)
        }.v3Screen().navigationTitle("스캔 준비").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge:.bottom) {Button("준비됐어요 · 스캔 시작",action:startScan).buttonStyle(V3PrimaryButtonStyle()).padding(20).background(HearV3.canvas)}
    }
}

/// The three stages of a scan under the illustration (Figma 245:3178): dots on a hairline, numbered labels.
private struct ScanStepsRow:View {
    private let steps=["01 공간 스캔","02 기물·동선 설정","03 저장"]
    var body:some View {
        VStack(spacing:10) {
            ZStack {
                Rectangle().fill(HearV3.secondary.opacity(0.35)).frame(height:1)
                HStack {
                    ForEach(steps.indices,id:\.self) {i in
                        Circle().fill(HearV3.accent).frame(width:6,height:6)
                        if i < steps.count-1 {Spacer()}
                    }
                }
            }
            HStack {
                ForEach(steps.indices,id:\.self) {i in
                    Text(steps[i]).font(.system(size:12)).foregroundStyle(HearV3.secondary)
                    if i < steps.count-1 {Spacer()}
                }
            }
        }.accessibilityElement(children:.ignore).accessibilityLabel("순서: 공간 스캔, 기물과 동선 설정, 저장")
    }
}

/// An isometric stage with a dashed route from 출발 to 도착, drawn in the app's greys with the accent green.
private struct ScanStageIllustration:View {
    var body:some View {
        Canvas {context,size in
            let w=size.width, h=size.height
            // Floor parallelogram and the two back walls.
            let a=CGPoint(x:w*0.5,y:h*0.3), b=CGPoint(x:w*0.86,y:h*0.52), c=CGPoint(x:w*0.5,y:h*0.78), d=CGPoint(x:w*0.14,y:h*0.52)
            let wallH=h*0.2
            var left=Path(); left.move(to:d); left.addLine(to:a); left.addLine(to:CGPoint(x:a.x,y:a.y-wallH)); left.addLine(to:CGPoint(x:d.x,y:d.y-wallH)); left.closeSubpath()
            var right=Path(); right.move(to:a); right.addLine(to:b); right.addLine(to:CGPoint(x:b.x,y:b.y-wallH)); right.addLine(to:CGPoint(x:a.x,y:a.y-wallH)); right.closeSubpath()
            context.fill(left,with:.color(.white.opacity(0.06))); context.fill(right,with:.color(.white.opacity(0.1)))
            var floor=Path(); floor.move(to:a); floor.addLine(to:b); floor.addLine(to:c); floor.addLine(to:d); floor.closeSubpath()
            context.fill(floor,with:.color(.white.opacity(0.16)))
            context.stroke(floor,with:.color(.white.opacity(0.5)),lineWidth:1)
            // Two boxes on the floor.
            func box(_ origin:CGPoint,_ dx:CGFloat,_ dy:CGFloat,_ height:CGFloat) {
                let p0=origin, p1=CGPoint(x:p0.x+dx,y:p0.y+dy*0.6), p2=CGPoint(x:p1.x-dx*0.7,y:p1.y+dy), p3=CGPoint(x:p0.x-dx*0.7,y:p0.y+dy)
                var top=Path(); top.move(to:CGPoint(x:p0.x,y:p0.y-height)); top.addLine(to:CGPoint(x:p1.x,y:p1.y-height)); top.addLine(to:CGPoint(x:p2.x,y:p2.y-height)); top.addLine(to:CGPoint(x:p3.x,y:p3.y-height)); top.closeSubpath()
                var front=Path(); front.move(to:CGPoint(x:p3.x,y:p3.y-height)); front.addLine(to:CGPoint(x:p2.x,y:p2.y-height)); front.addLine(to:p2); front.addLine(to:p3); front.closeSubpath()
                var side=Path(); side.move(to:CGPoint(x:p2.x,y:p2.y-height)); side.addLine(to:CGPoint(x:p1.x,y:p1.y-height)); side.addLine(to:p1); side.addLine(to:p2); side.closeSubpath()
                context.fill(front,with:.color(.white.opacity(0.22))); context.fill(side,with:.color(.white.opacity(0.14))); context.fill(top,with:.color(.white.opacity(0.4)))
            }
            box(CGPoint(x:w*0.6,y:h*0.36),w*0.14,h*0.1,h*0.1)
            box(CGPoint(x:w*0.42,y:h*0.36),w*0.07,h*0.06,h*0.07)
            // The route: 출발 → P1 → P2 → P3 → 도착.
            let route=[CGPoint(x:w*0.28,y:h*0.58),CGPoint(x:w*0.42,y:h*0.66),CGPoint(x:w*0.52,y:h*0.58),CGPoint(x:w*0.62,y:h*0.5),CGPoint(x:w*0.72,y:h*0.56)]
            var line=Path(); line.addLines(route)
            context.stroke(line,with:.color(HearV3.accent),style:StrokeStyle(lineWidth:2,dash:[5,4]))
            let labels=["출발","P1","P2","P3","도착"]
            for (i,p) in route.enumerated() {
                let end=i == 0 || i == route.count-1
                let r: CGFloat = end ? 9 : 8
                context.fill(Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2)),with:.color(i == route.count-1 ? Color(red:1,green:69/255,blue:58/255) : HearV3.accent))
                if end {
                    context.draw(Text(labels[i]).font(.system(size:9,weight:.bold)).foregroundColor(.white),at:CGPoint(x:p.x,y:p.y-r-8))
                    context.draw(Text(Image(systemName:i == 0 ? "figure.walk" : "checkmark")).font(.system(size:9,weight:.bold)).foregroundColor(.black),at:p)
                } else {
                    context.draw(Text(labels[i]).font(.system(size:8,weight:.bold)).foregroundColor(.black),at:p)
                }
            }
        }.padding(16)
    }
}
