import Foundation
import Accelerate
import CoreML
import CryptoKit

// Native port of the pinned Plus coreml/ane/bark_coreml.py reference.
// Encoder weights, mel filters, LSTM gates and TDT duration rules remain the publisher's.
private struct PlusWeightSpec: Decodable {
    let file: String
    let shape: [Int]
    let sha256: String
}

private struct PlusVocabulary: Decodable {
    let pieces: [String]
    let vocab_size: Int
    let blank_id: Int
    let durations: [Int]
    let max_symbols_per_step: Int
    let special_ids: [Int]
}

private struct PlusMatrix {
    let values: [Float]
    let rows: Int
    let columns: Int
    func multiply(_ vector: [Float], adding bias: [Float]) -> [Float] {
        precondition(vector.count == columns && bias.count == rows)
        var result = bias
        cblas_sgemv(CblasRowMajor, CblasNoTrans, Int32(rows), Int32(columns), 1,
                    values, Int32(columns), vector, 1, 1, &result, 1)
        return result
    }
}

final class PlusFrontend {
    private let mel: [Float]
    private let window: [Float]
    private let fft: vDSP_DFT_Setup

    init(mel: [Float]) throws {
        guard mel.count == 128 * 257,
              let setup = vDSP_DFT_zop_CreateSetup(nil, 512, .FORWARD) else {
            throw FlowError("Could not initialize the Plus audio frontend.")
        }
        self.fft = setup
        self.mel = mel
        var window = [Float](repeating: 0, count: 512)
        for i in 0..<400 { window[56 + i] = Float(0.5 - 0.5 * cos(2 * Double.pi * Double(i) / 399)) }
        self.window = window
    }
    deinit { vDSP_DFT_DestroySetup(fft) }

    func features(_ samples: [Float]) -> (values: [Float], frames: Int, valid: Int) {
        let valid = samples.count / 160
        let frames = 1 + samples.count / 160
        var emphasized = samples
        for i in 1..<samples.count { emphasized[i] = samples[i] - 0.97 * samples[i-1] }
        var power = [Float](repeating: 0, count: frames * 257)
        var real = [Float](repeating: 0, count: 512)
        let imaginary = [Float](repeating: 0, count: 512)
        var outputReal = real, outputImaginary = real
        for frame in 0..<frames {
            let start = frame * 160 - 256
            for j in 0..<512 {
                let at = start + j
                real[j] = at >= 0 && at < emphasized.count ? emphasized[at] * window[j] : 0
            }
            vDSP_DFT_Execute(fft, real, imaginary, &outputReal, &outputImaginary)
            for k in 0..<257 { power[frame * 257 + k] = outputReal[k] * outputReal[k] + outputImaginary[k] * outputImaginary[k] }
        }
        var features = [Float](repeating: 0, count: frames * 128)
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(frames), 128, 257,
                    1, power, 257, mel, 257, 0, &features, 128)
        for i in features.indices { features[i] = log(features[i] + 1.0 / 16_777_216.0) }
        for band in 0..<128 {
            var mean: Float = 0
            for frame in 0..<valid { mean += features[frame * 128 + band] }
            mean /= Float(max(1, valid))
            var variance: Float = 0
            for frame in 0..<valid {
                let delta = features[frame * 128 + band] - mean
                variance += delta * delta
            }
            let denominator = sqrt(variance / Float(max(1, valid - 1))) + 0.00001
            for frame in 0..<valid { features[frame * 128 + band] = (features[frame * 128 + band] - mean) / denominator }
            for frame in valid..<frames { features[frame * 128 + band] = 0 }
        }
        return (features, frames, valid)
    }
}

final class PlusRuntime {
    private let root: URL
    private let vocabulary: PlusVocabulary
    private let embedding: PlusMatrix
    private let inputWeights: [PlusMatrix]
    private let recurrentWeights: [PlusMatrix]
    private let biases: [[Float]]
    private let projector: PlusMatrix
    private let projectorBias: [Float]
    private let head: PlusMatrix
    private let headBias: [Float]
    let frontend: PlusFrontend
    private var encoders: [Int: MLModel] = [:]
    private let compiled: URL
    private let units: MLComputeUnits

    init(root: URL, compiled: URL, units: MLComputeUnits) throws {
        self.root = root; self.compiled = compiled; self.units = units
        vocabulary = try JSONDecoder().decode(PlusVocabulary.self, from: Data(contentsOf: root.appendingPathComponent("vocab.json")))
        let folder = root.appendingPathComponent("decoder-data")
        let metadata = try JSONDecoder().decode([String: PlusWeightSpec].self,
            from: Data(contentsOf: folder.appendingPathComponent("weights.json")))
        func read(_ key: String) throws -> PlusMatrix {
            guard let spec = metadata[key], !spec.file.contains("/"), !spec.shape.isEmpty,
                  spec.shape.allSatisfy({ $0 > 0 }), spec.shape.count <= 2 else {
                throw FlowError("Missing Plus decoder weight: \(key). Reinstall the model.")
            }
            let data = try Data(contentsOf: folder.appendingPathComponent(spec.file), options: .mappedIfSafe)
            let count = spec.shape.reduce(1, *)
            guard data.count == count * 4,
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == spec.sha256 else {
                throw FlowError("Plus decoder integrity check failed: \(key).")
            }
            var values = [Float](repeating: 0, count: count)
            _ = values.withUnsafeMutableBytes { data.copyBytes(to: $0) }
            return PlusMatrix(values: values, rows: spec.shape[0], columns: spec.shape.count == 2 ? spec.shape[1] : 1)
        }
        embedding = try read("decoder.embedding.weight")
        inputWeights = try (0..<2).map { try read("decoder.lstm.weight_ih_l\($0)") }
        recurrentWeights = try (0..<2).map { try read("decoder.lstm.weight_hh_l\($0)") }
        biases = try (0..<2).map { layer in
            let a = try read("decoder.lstm.bias_ih_l\(layer)").values
            let b = try read("decoder.lstm.bias_hh_l\(layer)").values
            return zip(a,b).map(+)
        }
        projector = try read("decoder.decoder_projector.weight")
        projectorBias = try read("decoder.decoder_projector.bias").values
        head = try read("joint.head.weight"); headBias = try read("joint.head.bias").values
        frontend = try PlusFrontend(mel: read("mel_filters").values)
        guard embedding.columns == 640, embedding.rows > vocabulary.blank_id,
              vocabulary.blank_id >= 0, vocabulary.vocab_size > 0,
              head.rows == vocabulary.vocab_size + vocabulary.durations.count,
              head.columns == 640, vocabulary.max_symbols_per_step > 0 else {
            throw FlowError("The Plus decoder has an incompatible shape.")
        }
    }

    func warm(progress: @escaping @Sendable (String) async -> Void) async throws {
        for window in [8,15] {
            await progress("Loading Plus \(window)-second encoder…")
            encoders[window] = try loadEncoder(window)
        }
        // Make the first prediction before announcing Ready, so first-use compilation
        // does not surprise the user after they finish their first dictation.
        await progress("Warming up Bark 3.0 Plus…")
        _ = try encode(Array(repeating: Float(0), count: 8_000), window: 8)
        _ = try encode(Array(repeating: Float(0), count: 128_000), window: 15)
    }

    private func loadEncoder(_ window: Int) throws -> MLModel {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = units
        configuration.functionName = "w\(window)"
        return try MLModel(contentsOf: compiled, configuration: configuration)
    }

    func encode(_ padded: [Float], window: Int) throws -> [[Float]] {
        guard let encoder = encoders[window] else { throw FlowError("Plus is not ready yet.") }
        let features = frontend.features(padded)
        let time = window * 100 + 1
        guard features.frames <= time else { throw FlowError("Plus audio window is too long.") }
        let f = try MLMultiArray(shape: [1,NSNumber(value: time),128], dataType: .float16)
        let mask = try MLMultiArray(shape: [1,NSNumber(value: time)], dataType: .int32)
        let fp = f.dataPointer.assumingMemoryBound(to: Float16.self)
        fp.update(repeating: 0, count: time * 128)
        for i in features.values.indices { fp[i] = Float16(features.values[i]) }
        let mp = mask.dataPointer.assumingMemoryBound(to: Int32.self)
        mp.update(repeating: 0, count: time)
        for i in 0..<features.valid { mp[i] = 1 }
        let result = try encoder.prediction(from: MLDictionaryFeatureProvider(dictionary: ["features": f, "mask": mask]))
        guard let encoded = result.featureValue(for: "encoded")?.multiArrayValue,
              encoded.shape.count == 3, encoded.shape[2].intValue == 640 else {
            throw FlowError("Plus returned an unexpected encoder result.")
        }
        var length = features.valid
        for _ in 0..<3 { length = (length - 1) / 2 + 1 }
        length = min(length, encoded.shape[1].intValue)
        let ts = encoded.strides[1].intValue, cs = encoded.strides[2].intValue
        var output = [[Float]](repeating: [Float](repeating: 0, count: 640), count: length)
        for t in 0..<length {
            for c in 0..<640 {
                let index = t * ts + c * cs
                let value: Float
                switch encoded.dataType {
                case .float16: value = Float(encoded.dataPointer.assumingMemoryBound(to: Float16.self)[index])
                case .float32: value = encoded.dataPointer.assumingMemoryBound(to: Float.self)[index]
                default: throw FlowError("Plus returned an unsupported numeric format.")
                }
                guard value.isFinite else { throw FlowError("Plus returned non-finite audio features.") }
                output[t][c] = value
            }
        }
        return output
    }

    func decode(_ encoded: [[Float]]) -> [Int] {
        let hidden = embedding.columns
        var states = (0..<2).map { _ in ([Float](repeating:0,count:hidden), [Float](repeating:0,count:hidden)) }
        func step(_ token: Int) -> [Float] {
            var x = Array(embedding.values[(token * hidden)..<((token + 1) * hidden)])
            for layer in 0..<2 {
                var gates = inputWeights[layer].multiply(x, adding: biases[layer])
                let recurrence = recurrentWeights[layer].multiply(states[layer].0, adding: [Float](repeating: 0, count: hidden * 4))
                for j in gates.indices { gates[j] += recurrence[j] }
                var h = [Float](repeating:0,count:hidden), c = h
                for j in 0..<hidden {
                    let i = 1 / (1 + exp(-gates[j]))
                    let f = 1 / (1 + exp(-gates[hidden + j]))
                    let g = tanh(gates[2 * hidden + j])
                    let o = 1 / (1 + exp(-gates[3 * hidden + j]))
                    c[j] = f * states[layer].1[j] + i * g
                    h[j] = o * tanh(c[j])
                }
                states[layer] = (h,c); x = h
            }
            return projector.multiply(x, adding: projectorBias)
        }
        var decoder = step(vocabulary.blank_id)
        var t = 0, symbols = 0
        var output: [Int] = []
        while t < encoded.count {
            let joined = zip(encoded[t], decoder).map { max(0, $0 + $1) }
            let logits = head.multiply(joined, adding: headBias)
            var token = 0
            for k in 1..<vocabulary.vocab_size where logits[k] > logits[token] { token = k }
            var durationIndex = 0
            for k in 1..<vocabulary.durations.count where logits[vocabulary.vocab_size+k] > logits[vocabulary.vocab_size+durationIndex] { durationIndex = k }
            var duration = vocabulary.durations[durationIndex]
            if token == vocabulary.blank_id { t += max(duration,1); symbols = 0 }
            else {
                output.append(token); decoder = step(token); symbols += 1
                if duration == 0 && symbols >= vocabulary.max_symbols_per_step { duration = 1 }
                if duration > 0 { symbols = 0 }
                t += duration
            }
        }
        return output
    }

    private func detokenize(_ tokens: [Int]) -> String {
        let special = Set(vocabulary.special_ids)
        return tokens.filter { $0 >= 0 && $0 < vocabulary.pieces.count && !special.contains($0) }
            .map { vocabulary.pieces[$0] }.joined().replacingOccurrences(of: "▁", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func segments(_ samples: [Float]) -> [Range<Int>] {
        let maximum = 236_000 // 14.75s leaves the reference 0.25s leading-silence allowance.
        guard samples.count > maximum else { return [0..<samples.count] }
        let frames = samples.count / 160
        var energy = [Float](repeating:0,count:frames)
        for frame in 0..<frames {
            var sum: Float = 0
            for j in 0..<160 { let v = samples[frame*160+j]; sum += v*v }
            energy[frame] = sum / 160
        }
        var smooth = energy
        for i in 0..<frames {
            smooth[i] = energy[max(0,i-10)..<min(frames,i+10)].reduce(0,+) / 20
        }
        var ranges: [Range<Int>] = [], start = 0
        while samples.count-start > maximum {
            let lo = (start+80_000)/160, hi = min(frames,(start+maximum)/160)
            var cut = lo
            for i in (lo+1)..<hi where smooth[i] < smooth[cut] { cut = i }
            let end = min(start+maximum,cut*160+80)
            ranges.append(start..<end); start = end
        }
        if start < samples.count { ranges.append(start..<samples.count) }
        return ranges
    }

    func transcribe(_ samples: [Float]) throws -> String {
        try Self.segments(samples).map { range in
            let padded = [Float](repeating:0,count:4000) + samples[range]
            let window = padded.count <= 128_000 ? 8 : 15
            return detokenize(decode(try encode(padded, window: window)))
        }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}
