import Foundation
import SceneKit
import AppKit

// Offline conversion of the supplied static, single-mesh glTF 2 assets. No runtime glTF dependency.
func convert(_ source: String, _ name: String, _ targetHeight: Float) throws {
 let data=try Data(contentsOf:URL(fileURLWithPath:source))
 func uint(_ offset:Int)->UInt32 {data.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:offset,as:UInt32.self)}}
 let jsonSize=Int(uint(12)), root=try JSONSerialization.jsonObject(with:data.subdata(in:20..<20+jsonSize)) as! [String:Any]
 precondition(root["skins"]==nil && root["animations"]==nil,"Animated assets need a skin-preserving converter")
 let bin=20+jsonSize+8, views=root["bufferViews"] as! [[String:Any]], accessors=root["accessors"] as! [[String:Any]]
 let meshes=root["meshes"] as! [[String:Any]], primitives=meshes[0]["primitives"] as! [[String:Any]], primitive=primitives[0]
 precondition(meshes.count==1 && primitives.count==1 && (root["nodes"] as! [[String:Any]]).count==1)
 let attributes=primitive["attributes"] as! [String:Int]
 func bytes(_ index:Int)->Data {
  let a=accessors[index],v=views[a["bufferView"] as! Int],start=bin+(v["byteOffset"] as? Int ?? 0)+(a["byteOffset"] as? Int ?? 0)
  precondition(v["byteStride"]==nil)
  return data.subdata(in:start..<start+(v["byteLength"] as! Int))
 }
 func floats(_ index:Int)->[Float] {let b=bytes(index);return stride(from:0,to:b.count,by:4).map {o in b.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:o,as:Float.self)}}}
 var positions=floats(attributes["POSITION"]!), normals=floats(attributes["NORMAL"]!), uv=floats(attributes["TEXCOORD_0"]!)
 let count=positions.count/3, height=stride(from:1,to:positions.count,by:3).map{positions[$0]}.max()!,scale=targetHeight/height
 for i in positions.indices {positions[i]*=scale}
 // Preserve glTF UVs: SceneKit image textures use the same orientation here.

 func src(_ values:[Float],_ semantic:SCNGeometrySource.Semantic,_ dimension:Int)->SCNGeometrySource {
  values.withUnsafeBytes { SCNGeometrySource(data:Data($0),semantic:semantic,vectorCount:count,usesFloatComponents:true,componentsPerVector:dimension,bytesPerComponent:4,dataOffset:0,dataStride:dimension*4) }
 }
 let index=primitive["indices"] as! Int, a=accessors[index], indices=bytes(index)
 let element=SCNGeometryElement(data:indices,primitiveType:.triangles,primitiveCount:(a["count"] as! Int)/3,bytesPerIndex:(a["componentType"] as! Int)==5125 ? 4:2)
 let geometry=SCNGeometry(sources:[src(positions,.vertex,3),src(normals,.normal,3),src(uv,.texcoord,2)],elements:[element])
 let imageInfo=(root["images"] as! [[String:Any]])[0],view=views[imageInfo["bufferView"] as! Int],start=bin+(view["byteOffset"] as? Int ?? 0)
 let imageData=data.subdata(in:start..<start+(view["byteLength"] as! Int))
 let image=NSImage(data:imageData)!,size=image.size,limit:CGFloat=name=="ReplayPerson" ? 2048:1024,ratio=min(1,limit/max(size.width,size.height))
 let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width*ratio),pixelsHigh:Int(size.height*ratio),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
 image.draw(in:NSRect(x:0,y:0,width:bitmap.pixelsWide,height:bitmap.pixelsHigh),from:.zero,operation:.copy,fraction:1)
 NSGraphicsContext.restoreGraphicsState()
 let directory=URL(fileURLWithPath:CommandLine.arguments[2]);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
 try bitmap.representation(using:.jpeg,properties:[.compressionFactor:0.88])!.write(to:directory.appendingPathComponent(name+".jpg"))
 let material=SCNMaterial();material.diffuse.contents=name+".jpg";material.roughness.contents=0.85;material.metalness.contents=0;material.isDoubleSided=true;material.lightingModel = .physicallyBased
 geometry.firstMaterial=material
 let scene=SCNScene();let node=SCNNode(geometry:geometry);node.name=name;scene.rootNode.addChildNode(node)
 precondition(scene.write(to:directory.appendingPathComponent(name+".scn"),options:nil,delegate:nil,progressHandler:nil))
 print(name,"triangles",element.primitiveCount,"height",targetHeight,"texture",bitmap.pixelsWide,bitmap.pixelsHigh)
}
// Usage: swift convert-replay-models.swift <source-directory> <output.scnassets>
precondition(CommandLine.arguments.count==3,"Pass source directory and output scnassets directory")
let sourceDirectory=URL(fileURLWithPath:CommandLine.arguments[1])
try convert(sourceDirectory.appendingPathComponent("시뮬레이션 인간 (기본형).glb").path,"ReplayPerson",1.7)
try convert(sourceDirectory.appendingPathComponent("영사기.glb").path,"ReplayProjector",0.32)
