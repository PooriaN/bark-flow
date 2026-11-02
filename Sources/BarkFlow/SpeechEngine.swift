import Foundation
import AVFoundation
import CoreML
import FluidAudio

struct FlowError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum AudioPolicy {
    static let sampleRate = 16_000.0
    static let maxSeconds = 600.0
    static let importMaxSeconds = 120.0
    static let minimumSeconds = 0.35
    static func hasSpeechEnergy(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return false }
        return samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count) > 0.000001
    }
}

// Only this actor owns Core ML objects. Loading and decoding never block the UI.
actor SpeechEngine {
    private var shared: (MLModel, MLModel, MLModel, [Int: String])?
    private var managers: [String: AsrManager] = [:]
    private var root: URL?
    private var compiledPaths: [String: URL] = [:]
    private var accelerator = "gpu"
    private var inferenceInFlight = false
    private var preparing = false
    private var choice: ModelChoice?
    private var plus: PlusRuntime?

    func prepare(root: URL, model: ModelChoice = .pro, accelerator: String = "gpu",
                 progress: @escaping @Sendable (String) async -> Void) async throws {
        if choice == model { return }
        guard !preparing && !inferenceInFlight else { throw FlowError("Wait for the current model operation to finish.") }
        preparing = true
        defer { preparing = false }
        // Retain one model at a time on the 16 GB Mac. A failed switch can be retried.
        choice = nil; plus = nil; managers.removeAll(); shared = nil; compiledPaths.removeAll()
        self.root = root
        self.accelerator = accelerator
        ModelHub.offlineMode = true
        let fm = FileManager.default
        if model != .pro {
            var compiled = root.appendingPathComponent("BarkEncoder.mlmodelc")
            if !fm.fileExists(atPath: compiled.path) {
                let cache = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("local.barkflow/\(model.rawValue)-\(model.revision)/\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)")
                try fm.createDirectory(at:cache, withIntermediateDirectories:true)
                compiled = cache.appendingPathComponent("BarkEncoder.mlmodelc")
                if !fm.fileExists(atPath:compiled.path) {
                    await progress("Preparing \(model.displayName)…")
                    let tmp = try await MLModel.compileModel(at:root.appendingPathComponent("BarkEncoder.mlpackage"))
                    defer { try? fm.removeItem(at:tmp) }
                    let staging = cache.appendingPathComponent(UUID().uuidString)
                    defer { try? fm.removeItem(at:staging) }
                    try fm.copyItem(at:tmp,to:staging); try fm.moveItem(at:staging,to:compiled)
                }
            }
            await progress("Loading \(model.displayName)…")
            let runtime = try PlusRuntime(root:root, compiled:compiled, units:.cpuAndNeuralEngine)
            try await runtime.warm(progress:progress)
            plus = runtime; choice = .plus
            return
        }
        guard fm.fileExists(atPath: root.appendingPathComponent("parakeet_v3_vocab.json").path) else {
            throw FlowError("Bark 3.0 Pro model files are missing. Keep the Models folder inside the app and try again.")
        }
        for name in ["Preprocessor", "Decoder", "JointDecisionv3", "Encoder"] {
            let bundled = root.appendingPathComponent(name + ".mlmodelc")
            if fm.fileExists(atPath: bundled.path) {
                compiledPaths[name] = bundled
                continue
            }
            // Source builds compile into a user cache, never into a signed app bundle.
            let cache = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("local.barkflow/4b5c51e04aa8d16d/\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)")
            try fm.createDirectory(at: cache, withIntermediateDirectories: true)
            let cached = cache.appendingPathComponent(name + ".mlmodelc")
            if !fm.fileExists(atPath: cached.path) {
                await progress("Preparing \(name.lowercased())…")
                let source = root.appendingPathComponent(name + ".mlpackage")
                guard fm.fileExists(atPath: source.path) else { throw FlowError("Missing model: \(name). Reinstall Bark Flow.") }
                let temporary = try await MLModel.compileModel(at: source)
                defer { try? fm.removeItem(at: temporary) }
                let staging = cache.appendingPathComponent(name + "." + UUID().uuidString + ".staging")
                defer { try? fm.removeItem(at: staging) }
                try fm.copyItem(at: temporary, to: staging)
                try fm.moveItem(at: staging, to: cached)
            }
            compiledPaths[name] = cached
        }
        await progress("Loading Bark 3.0 Pro…")
        let raw = try JSONDecoder().decode([String: String].self,
            from: Data(contentsOf: root.appendingPathComponent("parakeet_v3_vocab.json")))
        let vocabulary = Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in Int(k).map { ($0, v) } })
        shared = (try load("Preprocessor", units: .cpuOnly), try load("Decoder", units: .cpuOnly),
                  try load("JointDecisionv3", units: .cpuOnly), vocabulary)
        // Prepare both windows before Ready. Previously full15 was loaded only after
        // the user stopped their first longer dictation, causing a large first-use delay.
        for (function,count) in [("short8",16_000),("full15",144_000)] {
            await progress("Warming up Pro \(function == "short8" ? "short" : "long") dictation…")
            let engine = try manager(function:function)
            var state = try TdtDecoderState()
            _ = try await engine.transcribe([Float](repeating:0,count:count),decoderState:&state)
        }
        choice = .pro
    }

    private func load(_ name: String, units: MLComputeUnits, function: String? = nil) throws -> MLModel {
        guard let path = compiledPaths[name] else { throw FlowError("The speech model is not ready yet.") }
        let config = MLModelConfiguration()
        config.computeUnits = units
        config.functionName = function
        return try MLModel(contentsOf: path, configuration: config)
    }

    private func manager(function: String) throws -> AsrManager {
        if let cached = managers[function] { return cached }
        guard let (preprocessor, decoder, joint, vocabulary) = shared else { throw FlowError("Load the model first.") }
        let units: MLComputeUnits = accelerator == "ane" ? .cpuAndNeuralEngine : .cpuAndGPU
        let encoder = try load("Encoder", units: units, function: function)
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        let models = AsrModels(encoder: encoder, preprocessor: preprocessor, decoder: decoder, joint: joint,
                              configuration: config, vocabulary: vocabulary, version: .ultra)
        let manager = AsrManager(models: models)
        managers[function] = manager
        return manager
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard samples.count >= Int(AudioPolicy.minimumSeconds * AudioPolicy.sampleRate) else {
            throw FlowError("That recording was too short. Speak for at least half a second and try again.")
        }
        guard samples.count <= Int((AudioPolicy.maxSeconds + 1) * AudioPolicy.sampleRate) else {
            throw FlowError("This recording exceeds the ten-minute maximum.")
        }
        guard AudioPolicy.hasSpeechEnergy(samples) else { throw FlowError("No speech was detected. Check your microphone and try again.") }
        guard !inferenceInFlight else { throw FlowError("A dictation is already being transcribed. Wait for it to finish.") }
        inferenceInFlight = true
        defer { inferenceInFlight = false }
        guard !preparing, let choice else { throw FlowError("Choose a model and wait until it is ready.") }
        if choice != .pro {
            guard let plus else { throw FlowError("Plus is not ready yet.") }
            return try plus.transcribe(samples)
        }
        // Padding, encoder functions, model version and decoder state match the publisher's runner.
        let padded = Array(repeating: Float(0), count: 4000) + samples
        let function = padded.count <= 128_000 ? "short8" : "full15"
        let engine = try manager(function: function)
        var state = try TdtDecoderState()
        let result = try await engine.transcribe(padded, decoderState: &state)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func transcribe(file: URL, maximumSeconds: TimeInterval = AudioPolicy.importMaxSeconds) async throws -> String {
        let input = try AVAudioFile(forReading: file)
        guard Double(input.length) / input.processingFormat.sampleRate <= maximumSeconds else {
            throw FlowError("Choose an audio clip shorter than two minutes.")
        }
        let converter = AudioConverter()
        return try await transcribe(converter.resampleAudioFile(file))
    }
}
