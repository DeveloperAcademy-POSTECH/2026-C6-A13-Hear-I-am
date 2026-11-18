import Foundation
import Compression

/// A flat container of named files. No directories, links or permissions travel, and every name is checked
/// against the few shapes a shared stage uses, so a received file can never write outside its import folder.
///
/// Layout: the magic, then entries of `path length (UInt16) · path · raw size (UInt64) · stored size (UInt64) ·
/// method (UInt8, 0 stored / 1 LZFSE) · bytes`, ended by a zero path length. Integers are big-endian.
enum StageShareArchive {
    static let magic=Data("HEARIAM1".utf8)
    /// The largest single file a stage holds is its mesh (21 MB in the largest scan seen on a device).
    static let maximumEntryBytes: UInt64=256_000_000
    static let maximumEntries=4_000

    struct Entry: Sendable {
        let path: String
        let offset: UInt64
        let rawSize: UInt64
        let storedSize: UInt64
        let compressed: Bool
    }

    static func invalid() -> LabError { LabError.invalid(L("공유 파일이 손상되었거나 Hear I am 파일이 아니에요.")) }

    /// `share.json`, `plans/<UUID>.json`, `scenes/<UUID>/<file>` and `scenes/<UUID>/photos/<UUID>[-thumb].jpg` only.
    static func isAllowed(_ path: String) -> Bool {
        let parts=path.split(separator:"/",omittingEmptySubsequences:false).map(String.init)
        func isUUID(_ s: String) -> Bool { UUID(uuidString:s)?.uuidString==s }
        func isPhoto(_ s: String) -> Bool {
            guard s.hasSuffix(".jpg") else { return false }
            let stem=String(s.dropLast(4))
            return isUUID(stem) || (stem.hasSuffix("-thumb") && isUUID(String(stem.dropLast(6))))
        }
        switch parts.count {
        case 1: return parts[0]=="share.json"
        case 2: return parts[0]=="plans" && parts[1].hasSuffix(".json") && isUUID(String(parts[1].dropLast(5)))
        case 3: return parts[0]=="scenes" && isUUID(parts[1]) && StageShareArchive.sceneFiles.contains(parts[2])
        case 4: return parts[0]=="scenes" && isUUID(parts[1]) && parts[2]=="photos" && isPhoto(parts[3])
        default: return false
        }
    }
    static let sceneFiles: Set<String>=["manifest.json","worldmap.bin","mesh.json","surface-colors.json"]

    final class Writer {
        private let handle: FileHandle
        private var paths=Set<String>()
        init(url: URL) throws {
            guard FileManager.default.createFile(atPath:url.path,contents:nil) else {
                throw LabError.invalid(L("공유 파일을 만들지 못했어요."))
            }
            handle=try FileHandle(forWritingTo:url)
            try handle.write(contentsOf:StageShareArchive.magic)
        }
        deinit { try? handle.close() }
        func add(_ data: Data, at path: String) throws {
            guard StageShareArchive.isAllowed(path), paths.insert(path).inserted,
                  UInt64(data.count)<=StageShareArchive.maximumEntryBytes, paths.count<=StageShareArchive.maximumEntries else {
                throw LabError.invalid(L("공유 파일에 넣을 수 없는 항목이에요."))
            }
            // Photos and the world map barely shrink; they travel as they are.
            let packed=StageShareArchive.compress(data)
            let stored=packed ?? data
            var header=Data()
            let name=Data(path.utf8)
            header.append(UInt16(name.count).bigEndianBytes); header.append(name)
            header.append(UInt64(data.count).bigEndianBytes); header.append(UInt64(stored.count).bigEndianBytes)
            header.append(packed==nil ? 0 : 1)
            try handle.write(contentsOf:header); try handle.write(contentsOf:stored)
        }
        func finish() throws {
            try handle.write(contentsOf:UInt16(0).bigEndianBytes)
            try handle.synchronize(); try handle.close()
        }
    }

    struct Reader: Sendable {
        let url: URL
        let entries: [String: Entry]
        init(url: URL) throws {
            self.url=url
            let handle=try FileHandle(forReadingFrom:url)
            defer { try? handle.close() }
            let fileSize=try handle.seekToEnd(); try handle.seek(toOffset:0)
            func read(_ count: Int) throws -> Data {
                guard let data=try handle.read(upToCount:count), data.count==count else { throw StageShareArchive.invalid() }
                return data
            }
            guard try read(StageShareArchive.magic.count)==StageShareArchive.magic else { throw StageShareArchive.invalid() }
            var entries=[String: Entry]()
            while true {
                let length=Int(try read(2).bigEndianValue(UInt16.self))
                if length==0 { break }
                guard length<=200, let path=String(data:try read(length),encoding:.utf8), StageShareArchive.isAllowed(path),
                      entries[path]==nil, entries.count<StageShareArchive.maximumEntries else { throw StageShareArchive.invalid() }
                let raw=try read(8).bigEndianValue(UInt64.self), stored=try read(8).bigEndianValue(UInt64.self)
                let method=try read(1)[0]
                let offset=try handle.offset()
                guard method<=1, raw<=StageShareArchive.maximumEntryBytes, stored<=StageShareArchive.maximumEntryBytes,
                      method==1 || stored==raw, offset<=fileSize, stored<=fileSize-offset else { throw StageShareArchive.invalid() }
                entries[path]=Entry(path:path,offset:offset,rawSize:raw,storedSize:stored,compressed:method==1)
                try handle.seek(toOffset:offset+stored)
            }
            self.entries=entries
        }
        func data(_ path: String) throws -> Data {
            guard let entry=entries[path] else { throw StageShareArchive.invalid() }
            let handle=try FileHandle(forReadingFrom:url)
            defer { try? handle.close() }
            try handle.seek(toOffset:entry.offset)
            guard let stored=try handle.read(upToCount:Int(entry.storedSize)), stored.count==Int(entry.storedSize) else { throw StageShareArchive.invalid() }
            guard entry.compressed else { return stored }
            return try StageShareArchive.decompress(stored,rawSize:Int(entry.rawSize))
        }
    }

    /// nil when compressing would not save anything.
    static func compress(_ data: Data) -> Data? {
        guard data.count>64 else { return nil }
        var out=Data(count:data.count)
        let written=out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to:UInt8.self).baseAddress!,data.count,
                                          src.bindMemory(to:UInt8.self).baseAddress!,data.count,nil,COMPRESSION_LZFSE)
            }
        }
        guard written>0, written<data.count else { return nil }
        return out.prefix(written)
    }
    /// The output buffer is the declared size plus one byte, so a stream that would expand past it is caught
    /// instead of filling memory.
    static func decompress(_ data: Data, rawSize: Int) throws -> Data {
        guard rawSize>0, !data.isEmpty else { throw invalid() }
        var out=Data(count:rawSize+1)
        let written=out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to:UInt8.self).baseAddress!,rawSize+1,
                                          src.bindMemory(to:UInt8.self).baseAddress!,data.count,nil,COMPRESSION_LZFSE)
            }
        }
        guard written==rawSize else { throw invalid() }
        return out.prefix(rawSize)
    }
}

private extension FixedWidthInteger {
    var bigEndianBytes: Data { withUnsafeBytes(of:bigEndian) { Data($0) } }
}
private extension Data {
    func bigEndianValue<T: FixedWidthInteger>(_ type: T.Type) -> T {
        T(bigEndian:withUnsafeBytes { $0.loadUnaligned(as:T.self) })
    }
}
