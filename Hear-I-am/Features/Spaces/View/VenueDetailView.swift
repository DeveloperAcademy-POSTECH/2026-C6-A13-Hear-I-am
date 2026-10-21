import SwiftUI
import HearIAmCore

struct RoomCard: View {
    let room: VenueRoom
    let detail: String
    var body: some View {
        HStack(spacing:14) {
            SpacePhotoView(photo:room.photos.first,height:86).frame(width:100).clipShape(RoundedRectangle(cornerRadius:12))
            VStack(alignment:.leading,spacing:5) {
                Text(room.name).font(.headline)
                Text(room.subtitle).font(.caption).foregroundStyle(.secondary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength:0);Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
        }.padding(12).background(.white,in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(.gray.opacity(0.2)))
    }
}
struct VenueDetailView: View {
    let venue: SpaceVenue
    @ObservedObject var library: StageLibrary
    private var mapURL: URL {
        var url=URLComponents(string:"https://maps.apple.com/")!
        url.queryItems=[URLQueryItem(name:"q",value:venue.name),URLQueryItem(name:"address",value:venue.address)]
        return url.url!
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                SpacePhotoGallery(photos:venue.photos)
                VStack(alignment:.leading,spacing:10) {
                    Text(venue.name).font(.title2.bold())
                    Label(venue.address,systemImage:"mappin.and.ellipse").foregroundStyle(.secondary)
                }
                HStack {
                    Link(destination:mapURL) {Label("지도 보기",systemImage:"map").frame(maxWidth:.infinity,minHeight:44)}
                    Divider().frame(height:24)
                    Link(destination:venue.source) {Label("공식 안내",systemImage:"arrow.up.right").frame(maxWidth:.infinity,minHeight:44)}
                }.padding(.vertical,6).overlay(alignment:.top) {Divider()}.overlay(alignment:.bottom) {Divider()}
                Text("내부 공간").font(.title2.bold())
                ForEach(venue.rooms) {room in
                    NavigationLink {RoomDetailView(venue:venue,room:room,library:library)} label:{
                        RoomCard(room:room,detail:library.bases(in:room.id).isEmpty ? "공간 정보만 등록됨" : "기본 공간 있음 · 내 공연 \(library.performances(in:room.id).count)개")
                    }.buttonStyle(.plain)
                }
                Text("공식 정보 확인 · \(venue.checkedOn)\n장소 정보와 실제 스캔은 별도로 관리됩니다.").font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }.navigationTitle("장소 정보").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.topBarTrailing) {
                Button {library.favoriteVenue(venue.id)} label:{Image(systemName:library.spacePreferences.favorites.contains(venue.id) ? "star.fill" : "star")}.accessibilityLabel("즐겨찾기 \(library.spacePreferences.favorites.contains(venue.id) ? "해제" : "추가")")
            }}
    }
}
