#!/usr/bin/env python3
"""Exercise the app's actual streaming PCM converter without a microphone or iOS device.
Requires macOS and Xcode. No generated file is written into the repository.
"""
from pathlib import Path
import os, subprocess, tempfile
root=Path(__file__).resolve().parents[1]
source=(root/'Hear-I-am/Features/VoiceRehearsal/Service/VoiceRecognitionService.swift').read_text()
converter=source[source.index('final class VoiceNarrationPCMConverter {'):]
meter_start=source.index('    private static func rootMeanSquare(')
meter_end=source.index('    func finish()',meter_start)
meter=source[meter_start:meter_end].replace('private static func rootMeanSquare','func rootMeanSquare')
test=r'''
func input(_ rate: Double, channels: AVAudioChannelCount, interleaved: Bool, start: Int, count: Int) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: interleaved)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1,count)))!
    buffer.frameLength = AVAudioFrameCount(count)
    let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
    for b in list.indices {
        let samples = list[b].mData!.assumingMemoryBound(to: Float.self)
        let width = interleaved ? Int(channels) : 1
        for i in 0..<count {
            for c in 0..<width {samples[i*width+c] = Float(sin(Double(start+i)*2*Double.pi*440/rate)*0.25)}
        }
    }
    return buffer
}
func output(rate: Double, channels: AVAudioChannelCount, interleaved: Bool, chunk: Int, converter: VoiceNarrationPCMConverter) throws -> [Float] {
    var result: [Float] = []
    let total=Int(rate)
    func collect(_ buffers: [AVAudioPCMBuffer]) {
        for b in buffers {
            precondition(b.format.sampleRate == 48000 && b.format.channelCount == 1)
            result += Array(UnsafeBufferPointer(start:b.floatChannelData![0], count:Int(b.frameLength)))
        }
    }
    for i in stride(from:0,to:total,by:chunk) {
        collect(try converter.convert(input(rate,channels:channels,interleaved:interleaved,start:i,count:min(chunk,total-i))))
    }
    collect(try converter.convert(input(rate,channels:channels,interleaved:interleaved,start:0,count:0)))
    return result
}
for (rate,channels,interleaved) in [(22050.0,1,false),(24000,1,false),(44100,1,false),(48000,1,false),(44100,2,true),(48000,2,false)] {
    let converter=VoiceNarrationPCMConverter()
    let chunked=try output(rate:rate,channels:AVAudioChannelCount(channels),interleaved:interleaved,chunk:731,converter:converter)
    let whole=try output(rate:rate,channels:AVAudioChannelCount(channels),interleaved:interleaved,chunk:Int(rate),converter:VoiceNarrationPCMConverter())
    precondition(abs(chunked.count-48000)<=2, "wrong duration: \(chunked.count)")
    precondition(chunked.count==whole.count, "chunks changed duration")
    let difference=zip(chunked,whole).map {abs($0-$1)}.max() ?? 0
    precondition(difference<0.00001, "chunk discontinuity: \(difference)")
    precondition(chunked.allSatisfy {$0.isFinite && abs($0)<0.5})
    let crossings=zip(chunked.dropFirst(),chunked).filter {$0.0>0 && $0.1<=0}.count
    precondition(abs(crossings-440)<=2, "pitch changed")
    converter.reset()
    let second=try output(rate:24000,channels:1,interleaved:false,chunk:1024,converter:converter)
    precondition(abs(second.count-48000)<=2, "reset failed")
    print("PASS \(rate) Hz / \(channels) channels / interleaved=\(interleaved): \(chunked.count) frames; max chunk difference \(difference)")
}
let empty=VoiceNarrationPCMConverter()
precondition(try empty.convert(input(24000,channels:1,interleaved:false,start:0,count:0)).isEmpty)
let changed=VoiceNarrationPCMConverter()
_ = try changed.convert(input(24000,channels:1,interleaved:false,start:0,count:731))
do {
    _ = try changed.convert(input(44100,channels:1,interleaved:false,start:0,count:731))
    fatalError("mid-utterance format change was accepted")
} catch {print("PASS empty utterance and mid-utterance format rejection")}
'''
test += r'''
// Meter the same PCM layouts supplied by built-in microphones and Bluetooth HFP. Reading the
// existing input buffer must not alter audio forwarded to the recognizer.
for (rate, channels, interleaved) in [(16000.0,1,false),(48000,1,false),(48000,2,false),(48000,2,true)] {
    let buffer=input(rate,channels:AVAudioChannelCount(channels),interleaved:interleaved,start:0,count:1024)
    let data=buffer.floatChannelData!
    for frame in 0..<1024 {
        for channel in 0..<channels {
            if interleaved {data[0][frame*channels+channel]=Float(channel+1)*0.2}
            else {data[channel][frame]=Float(channel+1)*0.2}
        }
    }
    let expected=sqrt((1...channels).map {pow(Double($0)*0.2,2)}.reduce(0,+)/Double(channels))
    precondition(abs(rootMeanSquare(buffer)-expected)<0.00001)
    precondition(data[0][0] == Float(0.2), "meter mutated microphone PCM")
    print("PASS microphone RMS \(rate) Hz / \(channels) channels / interleaved=\(interleaved)")
}
'''
# Swift preconditions do not accept throwing expressions.
test=test.replace('precondition(try empty.convert(input(24000,channels:1,interleaved:false,start:0,count:0)).isEmpty)','let emptyOutput = try empty.convert(input(24000,channels:1,interleaved:false,start:0,count:0))\nprecondition(emptyOutput.isEmpty)')
env={**os.environ,'DEVELOPER_DIR':os.environ.get('DEVELOPER_DIR','/Applications/Xcode.app/Contents/Developer')}
with tempfile.TemporaryDirectory(prefix='voice69-audio-') as tmp:
    path=Path(tmp)/'main.swift'
    path.write_text('import AVFoundation\nimport Accelerate\n'+converter+'\n'+meter+'\n'+test)
    binary=str(Path(tmp)/'validate')
    subprocess.run(['xcrun','swiftc',str(path),'-o',binary],env=env,check=True)
    subprocess.run([binary],env=env,check=True)
