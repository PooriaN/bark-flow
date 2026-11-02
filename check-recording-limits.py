#!/usr/bin/env python3
"""Run the actual recorder limit logic with synthetic buffers; no microphone is opened."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent
harness = '\nstruct AudioPolicy { static let sampleRate = 16_000.0 }\nstruct FlowError: LocalizedError { let message:String; init(_ s:String){message=s}; var errorDescription:String? { message } }\nfinal class Counter: @unchecked Sendable { var value = 0 }\nextension MicrophoneRecorder {\n    func testLimit(seconds: Int) -> Bool {\n        let fmt = AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:16_000,channels:1,interleaved:false)!\n        converter = AVAudioConverter(from:fmt,to:fmt)\n        maximumSamples = seconds * 16_000\n        samples = []; failure = nil; limitNotified = false; accepting = true\n        let counter=Counter(); onLimit = { counter.value += 1 }\n        let count=AVAudioFrameCount(160_000)\n        let buffer=AVAudioPCMBuffer(pcmFormat:fmt,frameCapacity:count)!\n        buffer.frameLength=count\n        buffer.floatChannelData![0].update(repeating:0.01,count:Int(count))\n        for _ in 0..<(seconds/10+1) { consume(buffer) }\n        return failure == nil && samples.count == maximumSamples && counter.value == 1\n    }\n}\nfor seconds in [30,60,120,300,600] {\n    let recorder=MicrophoneRecorder()\n    precondition(recorder.testLimit(seconds:seconds),"limit failed: \\(seconds)")\n    print("PASS recording limit \\(seconds)s")\n}\n'
with tempfile.TemporaryDirectory(prefix="barkflow-recorder-check-") as work:
    temp = Path(work)
    source = temp / "check.swift"
    source.write_text((root / "Sources/BarkFlow/Recorder.swift").read_text() + harness)
    binary = temp / "check"
    subprocess.run(["swiftc", "-O", "-swift-version", "5", "-module-cache-path", str(temp / "cache"), str(source), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
