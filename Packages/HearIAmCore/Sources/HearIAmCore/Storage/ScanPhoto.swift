import Foundation

/// Camera pose is in the same AR world as the saved mesh. Pixels are upright JPEGs.
public struct ScanPhoto: Codable, Equatable, Identifiable, Sendable {
    public static let maximumCount=40
    public static let maximumImageBytes=8_000_000
    public static let maximumThumbnailBytes=500_000
    public let id: UUID
    public let capturedAt: Date
    public let frameTimestamp: Double
    public let cameraTransform: [Float]
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let imageHash: String
    public let thumbnailHash: String
    public let projection: ScanPhotoProjection?
    public let objectID: UUID?
    public let routePointIndex: Int?
    public init(id: UUID = UUID(), capturedAt: Date, frameTimestamp: Double, cameraTransform: [Float],
                pixelWidth: Int, pixelHeight: Int, imageHash: String, thumbnailHash: String,
                objectID: UUID? = nil, routePointIndex: Int? = nil, projection: ScanPhotoProjection? = nil) {
        self.id=id; self.capturedAt=capturedAt; self.frameTimestamp=frameTimestamp
        self.cameraTransform=cameraTransform; self.pixelWidth=pixelWidth; self.pixelHeight=pixelHeight
        self.imageHash=imageHash; self.thumbnailHash=thumbnailHash
        self.objectID=objectID; self.routePointIndex=routePointIndex; self.projection=projection
    }
    public var position: Point3 { Point3(Double(cameraTransform[12]),Double(cameraTransform[13]),Double(cameraTransform[14])) }
    public var forward: Point3 { Point3(-Double(cameraTransform[8]),-Double(cameraTransform[9]),-Double(cameraTransform[10])) }
    public func validate() throws {
        try projection?.validate()
        guard cameraTransform.count == 16, cameraTransform.allSatisfy(\.isFinite),
              abs(cameraTransform[3])<0.001, abs(cameraTransform[7])<0.001,
              abs(cameraTransform[11])<0.001, abs(cameraTransform[15]-1)<0.001,
              frameTimestamp.isFinite, frameTimestamp>=0, capturedAt.timeIntervalSince1970.isFinite,
              (1...4096).contains(pixelWidth), (1...4096).contains(pixelHeight),
              [imageHash,thumbnailHash].allSatisfy({$0.count==64 && $0.allSatisfy(\.isHexDigit)}),
              routePointIndex.map({$0>=0}) ?? true else {
            throw LabError.invalid("사진의 촬영 정보가 올바르지 않습니다.")
        }
        // A rigid pose must not contain scale/shear or a collapsed direction.
        for col in 0..<3 {
            let length=(0..<3).reduce(Float(0)) { $0+cameraTransform[col*4+$1]*cameraTransform[col*4+$1] }
            guard abs(length-1)<0.02 else { throw LabError.invalid("사진의 카메라 방향이 올바르지 않습니다.") }
            for other in (col+1)..<3 {
                let dot=(0..<3).reduce(Float(0)) { $0+cameraTransform[col*4+$1]*cameraTransform[other*4+$1] }
                guard abs(dot)<0.02 else { throw LabError.invalid("사진의 카메라 방향이 올바르지 않습니다.") }
            }
        }
    }
}

/// Temporary files are retained until the entire scan archive has been published.
public struct ScanPhotoSource: Sendable {
    public let photo: ScanPhoto
    public let imageURL: URL
    public let thumbnailURL: URL
    public init(photo: ScanPhoto, imageURL: URL, thumbnailURL: URL) {
        self.photo=photo; self.imageURL=imageURL; self.thumbnailURL=thumbnailURL
    }
}

/// Sensor intrinsics normalized to its original dimensions, before the JPEG is rotated/resized.
/// Optional on ScanPhoto so archives made before calibrated photo replay remain readable.
public struct ScanPhotoProjection: Codable, Equatable, Sendable {
    public let focalX: Double
    public let focalY: Double
    public let centerX: Double
    public let centerY: Double
    public let clockwiseQuarterTurns: Int
    public init(focalX: Double, focalY: Double, centerX: Double, centerY: Double, clockwiseQuarterTurns: Int) {
        self.focalX=focalX; self.focalY=focalY; self.centerX=centerX; self.centerY=centerY
        self.clockwiseQuarterTurns=clockwiseQuarterTurns
    }
    /// Intrinsics in the upright JPEG's coordinate system (origin at top left).
    public var upright: (fx: Double,fy: Double,cx: Double,cy: Double) {
        switch clockwiseQuarterTurns {
        case 1: return (focalY,focalX,1-centerY,centerX)
        case 2: return (focalX,focalY,1-centerX,1-centerY)
        case 3: return (focalY,focalX,centerY,1-centerX)
        default: return (focalX,focalY,centerX,centerY)
        }
    }
    public func validate() throws {
        guard [focalX,focalY,centerX,centerY].allSatisfy(\.isFinite),
              focalX>0,focalY>0,focalX<=100,focalY<=100,
              (0...1).contains(centerX),(0...1).contains(centerY),(0...3).contains(clockwiseQuarterTurns) else {
            throw LabError.invalid("사진의 화각 정보가 올바르지 않습니다.")
        }
    }
}
