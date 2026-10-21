import SwiftUI
import ImageIO
import CryptoKit
import HearIAmCore

/// Official source images are cached separately from user scans; offline reads keep cached photos.
private actor SpaceImageCache {
    static let shared=SpaceImageCache()
    private let memory=NSCache<NSURL,UIImage>()
    private let directory=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("VenuePhotos",isDirectory:true)
    init() {memory.totalCostLimit=24*1024*1024}
    func image(_ url: URL) async throws -> UIImage {
        if let image=memory.object(forKey:url as NSURL) {return image}
        let name=SHA256.hash(data:Data(url.absoluteString.utf8)).map {String(format:"%02x",$0)}.joined()
        let file=directory.appendingPathComponent(name)
        if let data=try? Data(contentsOf:file), let image=decode(data) {
            memory.setObject(image,forKey:url as NSURL,cost:Int(image.size.width*image.size.height*4));return image
        }
        var request=URLRequest(url:url);request.timeoutInterval=20
        let (fileURL,response)=try await URLSession.shared.download(for:request)
        defer {try? FileManager.default.removeItem(at:fileURL)}
        let size=(try? fileURL.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0
        guard let response=response as? HTTPURLResponse, response.statusCode==200,
              response.mimeType?.hasPrefix("image/")==true, size>0, size<=12*1024*1024 else {throw URLError(.cannotDecodeContentData)}
        let data=try Data(contentsOf:fileURL)
        guard let image=decode(data) else {throw URLError(.cannotDecodeContentData)}
        try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        // Store downsampled data, not an unbounded full-resolution original.
        if let jpeg=image.jpegData(compressionQuality:0.85) {try? jpeg.write(to:file,options:.atomic)}
        memory.setObject(image,forKey:url as NSURL,cost:Int(image.size.width*image.size.height*4))
        return image
    }
    private func decode(_ data: Data) -> UIImage? {
        guard let source=CGImageSourceCreateWithData(data as CFData,nil),
              let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:1400,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else {return nil}
        return UIImage(cgImage:cg)
    }
}

struct SpacePhotoView: View {
    let photo: SpacePhoto?
    var height: CGFloat=185
    @State private var image: UIImage?
    @State private var failed=false
    @State private var retry=0
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(.systemGray6)
                if let image {Image(uiImage:image).resizable().scaledToFill().frame(width:proxy.size.width,height:proxy.size.height).clipped()}
                else if failed || photo == nil {
                    VStack(spacing:6) {
                        Image(systemName:"photo").font(.title2)
                        Text("사진을 불러오지 못했어요").font(.caption)
                        if photo != nil {Button("다시 시도") {retry+=1}.font(.caption).frame(minHeight:44)}
                    }.foregroundStyle(.secondary)
                } else {ProgressView().accessibilityLabel("공간 사진 불러오는 중")}
            }
        }.frame(height:height).clipped()
            .task(id:"\(photo?.id ?? "")-\(retry)") {
                image=nil;failed=false
                guard let photo else {return}
                do {let value=try await SpaceImageCache.shared.image(photo.url);try Task.checkCancellation();image=value}
                catch {if !Task.isCancelled {failed=true}}
            }
            .accessibilityElement(children:image == nil ? .contain : .ignore)
            .accessibilityLabel(image == nil ? "공간 사진" : photo?.caption ?? "공간 사진")
    }
}

struct SpacePhotoGallery: View {
    let photos: [SpacePhoto]
    var height: CGFloat=190
    @State private var page=0
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            if photos.count>1 {
                TabView(selection:$page) {
                    ForEach(Array(photos.enumerated()),id:\.element.id) {index,photo in SpacePhotoView(photo:photo,height:height).tag(index)}
                }.frame(height:height).tabViewStyle(.page).clipShape(RoundedRectangle(cornerRadius:18))
            } else {SpacePhotoView(photo:photos.first,height:height).clipShape(RoundedRectangle(cornerRadius:18))}
            if let photo=photos.indices.contains(page) ? photos[page] : photos.first {
                if photo.caption.contains("외관") {Text(photo.caption).font(.caption).foregroundStyle(.secondary)}
                Link("사진 출처 · \(photo.credit) ↗",destination:photo.source).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
