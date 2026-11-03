import Foundation

enum ModelChoice: String, CaseIterable, Identifiable {
    case plus, standard, pro
    var id: String { rawValue }
    var displayName: String {
        switch self { case .plus: "Bark 3.0 Plus"; case .standard: "Bark 3.0"; case .pro: "Bark 3.0 Pro" }
    }
    var menuName: String {
        switch self { case .plus: "Plus · Included"; case .standard: "Bark 3.0 · Download"; case .pro: "Pro · Download" }
    }
    var folder: String { self == .plus ? "PlusModels" : self == .pro ? "Models" : "StandardModels" }
    var revision: String {
        switch self {
        case .plus: "d4fab2f8b95681e5ad3cfb4e8c5f4e0c009b3deb"
        case .standard: "85db2ad18ab41e534a222ee253c29191d77ed919"
        case .pro: "4b5c51e04aa8d16dda9ecdff71bc29f7360149e4"
        }
    }
    var installedDirectory: URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("Bark Flow/Models/\(rawValue)-\(revision)")
    }
    var availableDirectory: URL? {
        let fm = FileManager.default
        let compiled = self == .pro ? ["Encoder.mlmodelc/coremldata.bin","Preprocessor.mlmodelc/coremldata.bin","Decoder.mlmodelc/coremldata.bin","JointDecisionv3.mlmodelc/coremldata.bin","parakeet_v3_vocab.json"] : ["BarkEncoder.mlmodelc/coremldata.bin","decoder-data/weights.json","vocab.json"]
        let source = self == .pro ? ["Encoder.mlpackage/Manifest.json","Preprocessor.mlpackage/Manifest.json","Decoder.mlpackage/Manifest.json","JointDecisionv3.mlpackage/Manifest.json","parakeet_v3_vocab.json"] : ["BarkEncoder.mlpackage/Manifest.json","decoder-data/weights.json","vocab.json"]
        let bundled = Bundle.main.resourceURL!.appendingPathComponent(folder)
        if self == .plus && compiled.allSatisfy({ fm.fileExists(atPath:bundled.appendingPathComponent($0).path) }) { return bundled }
        let installed = installedDirectory
        if compiled.allSatisfy({ fm.fileExists(atPath:installed.appendingPathComponent($0).path) }) { return installed }
        if (try? String(contentsOf:installed.appendingPathComponent(".verified"), encoding:.utf8)) == revision && source.allSatisfy({ fm.fileExists(atPath:installed.appendingPathComponent($0).path) }) { return installed }
        if compiled.allSatisfy({ fm.fileExists(atPath:bundled.appendingPathComponent($0).path) }) || source.allSatisfy({ fm.fileExists(atPath:bundled.appendingPathComponent($0).path) }) { return bundled }
        return nil
    }
    var resourceDirectory: URL { availableDirectory ?? installedDirectory }
    static var saved: ModelChoice {
        ModelChoice(rawValue: UserDefaults.standard.string(forKey: "selectedModel") ?? "plus") ?? .plus
    }
}
