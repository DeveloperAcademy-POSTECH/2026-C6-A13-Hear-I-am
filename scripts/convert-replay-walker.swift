import Foundation
import SceneKit
import AppKit
import simd

// Offline, skin-preserving conversion for the supplied Mixamo GLB. Runtime uses native SceneKit.
// Usage: xcrun swift scripts/convert-replay-walker.swift <rigged.glb> <output.scnassets>
precondition(CommandLine.arguments.count == 3, "Pass a rigged GLB and output directory")
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
func uint(_ offset: Int) -> UInt32 { data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) } }
precondition(uint(0) == 0x46546C67 && uint(4) == 2 && Int(uint(8)) == data.count)
let jsonLength = Int(uint(12))
precondition(uint(16) == 0x4E4F534A && uint(24 + jsonLength) == 0x004E4942)
let root = try JSONSerialization.jsonObject(with: data.subdata(in: 20..<20 + jsonLength)) as! [String: Any]
let binary = 28 + jsonLength
let views = root["bufferViews"] as! [[String: Any]]
let accessors = root["accessors"] as! [[String: Any]]
let nodeInfo = root["nodes"] as! [[String: Any]]
let directory = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func values(_ index: Int) -> [[Float]] {
    let a = accessors[index], v = views[a["bufferView"] as! Int]
    precondition(a["sparse"] == nil && (v["buffer"] as? Int ?? 0) == 0)
    let components = ["SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16][a["type"] as! String]!
    let type = a["componentType"] as! Int
    let size = [5121: 1, 5123: 2, 5125: 4, 5126: 4][type]!
    let offset = a["byteOffset"] as? Int ?? 0, stride = v["byteStride"] as? Int ?? components * size
    let start = binary + (v["byteOffset"] as? Int ?? 0) + offset, count = a["count"] as! Int
    precondition(offset + (count - 1) * stride + components * size <= v["byteLength"] as! Int)
    return (0..<count).map { i in (0..<components).map { c in
        let p = start + i * stride + c * size
        return data.withUnsafeBytes { b in
            switch type {
            case 5121: return Float(b.loadUnaligned(fromByteOffset: p, as: UInt8.self))
            case 5123: return Float(b.loadUnaligned(fromByteOffset: p, as: UInt16.self))
            case 5125: return Float(b.loadUnaligned(fromByteOffset: p, as: UInt32.self))
            default: return b.loadUnaligned(fromByteOffset: p, as: Float.self)
            }
        }
    } }
}
func vector(_ a: [Float]) -> SIMD3<Float> { SIMD3(a[0], a[1], a[2]) }
func matrix(_ a: [Float]) -> simd_float4x4 {
    simd_float4x4(columns: (.init(a[0],a[1],a[2],a[3]), .init(a[4],a[5],a[6],a[7]),
                          .init(a[8],a[9],a[10],a[11]), .init(a[12],a[13],a[14],a[15])))
}
let nodes = nodeInfo.map { info -> SCNNode in
    let n = SCNNode(); n.name = info["name"] as? String
    if let m = info["matrix"] as? [Float] { n.simdTransform = matrix(m) }
    else {
        n.simdPosition = vector(info["translation"] as? [Float] ?? [0,0,0])
        n.simdScale = vector(info["scale"] as? [Float] ?? [1,1,1])
        let q = info["rotation"] as? [Float] ?? [0,0,0,1]
        n.simdOrientation = simd_quatf(vector: SIMD4(q[0],q[1],q[2],q[3]))
    }
    return n
}
for (i, info) in nodeInfo.enumerated() {
    for child in info["children"] as? [Int] ?? [] { nodes[i].addChildNode(nodes[child]) }
}
let meshes = root["meshes"] as! [[String: Any]], skins = root["skins"] as! [[String: Any]]
precondition(meshes.count == 1 && skins.count == 1, "Converter supports the supplied single-skin model")
let primitives = meshes[0]["primitives"] as! [[String: Any]]
precondition(primitives.count == 1 && (primitives[0]["mode"] as? Int ?? 4) == 4)
let primitive = primitives[0], attributes = primitive["attributes"] as! [String: Int]
let positions = values(attributes["POSITION"]!)
func source(_ key: String, _ semantic: SCNGeometrySource.Semantic) -> SCNGeometrySource {
    let v = values(attributes[key]!), flat = v.flatMap { $0 }
    return flat.withUnsafeBytes {
        SCNGeometrySource(data: Data($0), semantic: semantic, vectorCount: v.count,
            usesFloatComponents: true, componentsPerVector: v[0].count, bytesPerComponent: 4,
            dataOffset: 0, dataStride: v[0].count * 4)
    }
}
let indices = values(primitive["indices"] as! Int).map { UInt32($0[0]) }
let geometry = SCNGeometry(sources: [source("POSITION", .vertex), source("NORMAL", .normal), source("TEXCOORD_0", .texcoord)],
    elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
let joints = values(attributes["JOINTS_0"]!).flatMap { $0.map { UInt16($0) } }
let jointSource = joints.withUnsafeBytes {
    SCNGeometrySource(data: Data($0), semantic: .boneIndices, vectorCount: positions.count,
        usesFloatComponents: false, componentsPerVector: 4, bytesPerComponent: 2, dataOffset: 0, dataStride: 8)
}
let skin = skins[0], boneIDs = skin["joints"] as! [Int]
let skinner = SCNSkinner(baseGeometry: geometry, bones: boneIDs.map { nodes[$0] },
    boneInverseBindTransforms: values(skin["inverseBindMatrices"] as! Int).map { NSValue(scnMatrix4: SCNMatrix4(matrix($0))) },
    boneWeights: source("WEIGHTS_0", .boneWeights), boneIndices: jointSource)
let meshIndex = nodeInfo.firstIndex { $0["mesh"] as? Int == 0 }!
precondition(nodeInfo[meshIndex]["skin"] as? Int == 0)
nodes[meshIndex].geometry = geometry; nodes[meshIndex].skinner = skinner
let hipsIndex = nodeInfo.firstIndex { $0["name"] as? String == "mixamorig:Hips" }!
skinner.skeleton = nodes[hipsIndex]

let materialInfo = (root["materials"] as! [[String: Any]])[primitive["material"] as! Int]
let pbr = materialInfo["pbrMetallicRoughness"] as! [String: Any]
let textureIndex = (pbr["baseColorTexture"] as! [String: Any])["index"] as! Int
let imageIndex = (root["textures"] as! [[String: Any]])[textureIndex]["source"] as! Int
let imageView = views[(root["images"] as! [[String: Any]])[imageIndex]["bufferView"] as! Int]
let imageStart = binary + (imageView["byteOffset"] as? Int ?? 0)
let image = NSImage(data: data.subdata(in: imageStart..<imageStart + (imageView["byteLength"] as! Int)))!
let ratio = min(1, 2048 / max(image.size.width, image.size.height))
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * ratio), pixelsHigh: Int(image.size.height * ratio),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(in: NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh), from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.88])!.write(to: directory.appendingPathComponent("ReplayWalker.jpg"))
let material = SCNMaterial(); material.diffuse.contents = "ReplayWalker.jpg"
material.roughness.contents = 0.85; material.metalness.contents = 0; material.isDoubleSided = true; material.lightingModel = .physicallyBased
geometry.firstMaterial = material

let minimumY = positions.map { $0[1] }.min()!, maximumY = positions.map { $0[1] }.max()!
let scale: Float = 1.7 / (maximumY - minimumY)
let scene = SCNScene(), normalized = SCNNode(); normalized.name = "ReplayWalker"
normalized.simdScale = SIMD3(repeating: scale); normalized.simdPosition.y = -minimumY * scale
scene.rootNode.addChildNode(normalized)
let sceneInfo = (root["scenes"] as! [[String: Any]])[root["scene"] as? Int ?? 0]
for i in sceneInfo["nodes"] as! [Int] { normalized.addChildNode(nodes[i]) }
precondition(scene.write(to: directory.appendingPathComponent("ReplayWalker.scn"), options: nil, delegate: nil, progressHandler: nil))

let animation = (root["animations"] as! [[String: Any]])[0]
let samplers = animation["samplers"] as! [[String: Any]]
// A matching pair of gait poses inside the supplied clip, avoiding its lead-in and tail.
let loopStart = Float(17.0 / 24), loopEnd = Float(46.0 / 24)
var rootMotion: [[Float]] = [], rootTimes: [Float] = []
let tracks: [[String: Any]] = (animation["channels"] as! [[String: Any]]).map { channel in
    let target = channel["target"] as! [String: Any], id = target["node"] as! Int, path = target["path"] as! String
    let sampler = samplers[channel["sampler"] as! Int], interpolation = sampler["interpolation"] as? String ?? "LINEAR"
    precondition(["LINEAR", "STEP"].contains(interpolation) && ["rotation", "translation", "scale"].contains(path))
    let times = values(sampler["input"] as! Int).map { $0[0] }, v = values(sampler["output"] as! Int)
    precondition(times.count == v.count && zip(times, times.dropFirst()).allSatisfy { $0 < $1 })
    if id == hipsIndex && path == "translation" { rootMotion = v; rootTimes = times }
    return ["node": nodes[id].name!, "path": path, "interpolation": interpolation, "times": times, "values": v]
}
let first = rootTimes.indices.min { abs(rootTimes[$0] - loopStart) < abs(rootTimes[$1] - loopStart) }!
let last = rootTimes.indices.min { abs(rootTimes[$0] - loopEnd) < abs(rootTimes[$1] - loopEnd) }!
let strideMeters = hypot(rootMotion[last][0] - rootMotion[first][0], rootMotion[last][2] - rootMotion[first][2]) * scale
precondition(strideMeters > 0.5 && strideMeters < 3)
let clip: [String: Any] = ["version": 1, "name": animation["name"] as? String ?? "walk",
    "loopStart": loopStart, "loopEnd": loopEnd, "strideMeters": strideMeters,
    "rootName": nodes[hipsIndex].name!, "rootPosition": nodeInfo[hipsIndex]["translation"]!, "tracks": tracks]
try JSONSerialization.data(withJSONObject: clip, options: [.sortedKeys]).write(to: directory.appendingPathComponent("ReplayWalker.animation.json"))
print("ReplayWalker: \(indices.count / 3) triangles, \(boneIDs.count) bones, \(tracks.count) tracks, stride \(strideMeters)m, loop \(loopEnd - loopStart)s")
