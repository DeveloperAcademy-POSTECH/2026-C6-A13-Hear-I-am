import SwiftUI

enum HearRole: String, CaseIterable, Identifiable {
    case performer, helper
    var id:String {rawValue}
    var title:String {self == .performer ? "공연자" : "조력자"}
    var detail:String {self == .performer ? "음성 안내를 따라\n무대에서 이동해요." : "무대를 스캔하고\n공연 동선을 준비해요."}
}

struct HearLaunchView: View {
    var body: some View {
        VStack(spacing:16) {
            Image("HearV3Brand").resizable().scaledToFit().frame(width:144,height:144).accessibilityHidden(true)
            Text("Hear I am").font(.largeTitle.bold())
            Text("무대 위, 나의 다음 걸음").font(.subheadline).foregroundStyle(HearV3.secondary)
        }.frame(maxWidth:.infinity,maxHeight:.infinity).v3Screen().ignoresSafeArea()
            .accessibilityElement(children:.combine).accessibilityIdentifier("launch.brand")
    }
}

struct RoleSelectionView: View {
    let select:(HearRole)->Void
    @State private var selected:HearRole?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    Text("어떻게 사용하시겠어요?").font(.title.bold())
                    Text("사용할 역할을 하나 선택해주세요.").foregroundStyle(HearV3.secondary)
                    ForEach(HearRole.allCases) {role in
                        Button {selected=role} label: {
                            VStack(alignment:.leading,spacing:20) {
                                HStack {
                                    if role == .performer {
                                        Image(systemName:"headphones").font(.system(size:40)).frame(width:48,height:48)
                                    } else {
                                        Image("HearV3Scan").resizable().scaledToFit().frame(width:48,height:48)
                                    }
                                    Spacer()
                                    Image(systemName:selected == role ? "largecircle.fill.circle" : "circle").font(.title2)
                                }.accessibilityHidden(true)
                                VStack(alignment:.leading,spacing:8) {
                                    Text(role.title).font(.title2.bold())
                                    Text(role.detail).foregroundStyle(HearV3.secondary)
                                        .fixedSize(horizontal:false,vertical:true)
                                }
                            }.padding(24).frame(maxWidth:.infinity,alignment:.leading)
                                .background(selected == role ? HearV3.selected : HearV3.surface,in:RoundedRectangle(cornerRadius:24))
                                .overlay {RoundedRectangle(cornerRadius:24).stroke(selected == role ? HearV3.text : .clear,lineWidth:2)}
                        }.buttonStyle(.plain).accessibilityLabel("\(role.title), \(role.detail)")
                            .accessibilityAddTraits(selected == role ? .isSelected : [])
                            .accessibilityIdentifier("role.\(role.rawValue)")
                    }
                    Text("앱을 새로 실행할 때마다 역할을 선택해요. 저장한 공연과 기록은 유지돼요.")
                        .font(.footnote).foregroundStyle(HearV3.secondary)
                }.padding(20)
            }.navigationTitle("Hear I am").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge:.bottom) {
                    Button(selected.map {"\($0.title)로 시작하기"} ?? "역할을 선택해주세요") {
                        if let selected {select(selected)}
                    }.buttonStyle(V3PrimaryButtonStyle()).disabled(selected == nil)
                        .opacity(selected == nil ? 0.45 : 1).padding(20).background(HearV3.canvas)
                        .accessibilityIdentifier("role.continue")
                }.v3Screen()
        }.preferredColorScheme(.dark)
    }
}
