import Foundation
import AVFoundation

// A dedicated serial queue protects the capture buffer, converter and lifecycle.
// The tap only copies bounded audio; conversion happens away from the audio thread.
final class MicrophoneRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.barkflow.capture", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private var accepting = false
    private var failure: Error?
    private var maximumSamples = Int(120 * AudioPolicy.sampleRate)
    private var limitNotified = false
    var onLevel: (@Sendable (Float) -> Void)?
    var onLimit: (@Sendable () -> Void)?

    func start(maxSeconds: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    let engine = AVAudioEngine()
                    let input = engine.inputNode
                    let format = input.outputFormat(forBus: 0)
                    guard format.sampleRate > 0, format.channelCount > 0,
                          let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioPolicy.sampleRate,
                                                     channels: 1, interleaved: false),
                          let converter = AVAudioConverter(from: format, to: target) else {
                        throw FlowError("No working microphone was found. Select an input in System Settings > Sound.")
                    }
                    self.engine = engine
                    self.converter = converter
                    maximumSamples = Int(maxSeconds * AudioPolicy.sampleRate)
                    samples = []; failure = nil; limitNotified = false; accepting = true
                    input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
                        copy.frameLength = buffer.frameLength
                        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
                        let dest = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
                        for index in source.indices {
                            if let from = source[index].mData, let to = dest[index].mData {
                                memcpy(to, from, Int(source[index].mDataByteSize))
                            }
                        }
                        self?.queue.async { self?.consume(copy) }
                    }
                    engine.prepare()
                    try engine.start()
                    continuation.resume()
                } catch {
                    accepting = false
                    engine?.inputNode.removeTap(onBus: 0)
                    engine?.stop(); engine = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard accepting, let converter else { return }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * AudioPolicy.sampleRate / buffer.format.sampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .noDataNow; return nil }
            supplied = true; state.pointee = .haveData; return buffer
        }
        if status == .error { failure = error ?? FlowError("Microphone conversion failed."); return }
        guard let ptr = output.floatChannelData?[0] else { return }
        let remaining = maximumSamples - samples.count
        let count = min(remaining, Int(output.frameLength))
        guard count > 0 else { return }
        let chunk = UnsafeBufferPointer(start: ptr, count: count)
        samples.append(contentsOf: chunk)
        if samples.count >= maximumSamples && !limitNotified {
            limitNotified = true
            onLimit?()
        }
        let energy = chunk.reduce(Float(0)) { $0 + $1 * $1 } / Float(count)
        onLevel?(min(1, sqrt(energy) * 12))
    }

    func stop() async throws -> [Float] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                accepting = false
                engine?.inputNode.removeTap(onBus: 0)
                engine?.stop(); engine = nil; converter = nil
                let result = samples
                samples.removeAll(keepingCapacity: false)
                if let failure { continuation.resume(throwing: failure) }
                else { continuation.resume(returning: result) }
            }
        }
    }
}
