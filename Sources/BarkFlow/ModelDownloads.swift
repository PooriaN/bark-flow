import Foundation
import CryptoKit

private struct DownloadManifest: Decodable {
    struct File: Decodable {
        struct LFS: Decodable { let oid: String }
        let path: String
        let size: Int64
        let oid: String
        let lfs: LFS?
    }
    let repository: String
    let revision: String
    let files: [File]
}

enum ModelDownloads {
    static func ensureAvailable(_ model: ModelChoice, store: URL? = nil, progress: @escaping @Sendable (String) async -> Void) async throws -> URL {
        if store == nil, let existing = model.availableDirectory { return existing }
        guard model != .plus else { throw FlowError("The bundled Plus model is missing. Reinstall Bark Flow.") }
        guard let manifestURL = Bundle.main.url(forResource: model == .pro ? "ModelManifest" : "StandardModelManifest", withExtension: "json") else {
            throw FlowError("The model download manifest is missing. Reinstall Bark Flow.")
        }
        let manifest = try JSONDecoder().decode(DownloadManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.revision == model.revision else { throw FlowError("Model manifest revision mismatch.") }
        let fm = FileManager.default
        let destinationDirectory = store?.appendingPathComponent("\(model.rawValue)-\(model.revision)") ?? model.installedDirectory
        let parent = destinationDirectory.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".download-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        for (index, entry) in manifest.files.enumerated() {
            try Task.checkCancellation()
            let prefix = entry.path.hasPrefix("coreml/ane/") ? "coreml/ane/" : "coreml/"
            guard entry.path.hasPrefix(prefix) else { throw FlowError("Invalid model download path.") }
            let name = String(entry.path.dropFirst(prefix.count))
            guard !name.isEmpty, !name.split(separator: "/").contains(".."), !name.hasPrefix("/") else { throw FlowError("Invalid model download path.") }
            let destination = staging.appendingPathComponent(name)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let urlString = "https://huggingface.co/\(manifest.repository)/resolve/\(manifest.revision)/\(entry.path)?download=true"
            guard let url = URL(string: urlString) else { throw FlowError("Invalid model download URL.") }
            await progress("Downloading \(model.displayName) (file \(index + 1) of \(manifest.files.count))…")
            let (temporary, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw FlowError("Model download failed. Check your connection and try again.") }
            let size = (try fm.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value
            guard size == entry.size else { throw FlowError("Downloaded model file has an unexpected size. Try again.") }
            let input = try FileHandle(forReadingFrom: temporary)
            defer { try? input.close() }
            var sha256 = SHA256()
            var sha1 = Insecure.SHA1()
            if entry.lfs == nil { sha1.update(data: Data("blob \(entry.size)\0".utf8)) }
            while let data = try input.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
                try Task.checkCancellation()
                if entry.lfs != nil { sha256.update(data: data) } else { sha1.update(data: data) }
            }
            let actual = entry.lfs != nil ? sha256.finalize().map { String(format: "%02x", $0) }.joined() : sha1.finalize().map { String(format: "%02x", $0) }.joined()
            guard actual == (entry.lfs?.oid ?? entry.oid) else { throw FlowError("Model integrity check failed. Try downloading again.") }
            try fm.moveItem(at: temporary, to: destination)
        }
        if model == .standard {
            // The standard and Plus publisher manifests pin identical decoder and vocabulary files.
            guard let plus = ModelChoice.plus.availableDirectory else { throw FlowError("The bundled Plus decoder is missing. Reinstall Bark Flow.") }
            try fm.copyItem(at: plus.appendingPathComponent("decoder-data"), to: staging.appendingPathComponent("decoder-data"))
            try fm.copyItem(at: plus.appendingPathComponent("vocab.json"), to: staging.appendingPathComponent("vocab.json"))
        }
        try Data(manifest.revision.utf8).write(to: staging.appendingPathComponent(".verified"), options: .atomic)
        if fm.fileExists(atPath: destinationDirectory.path) { try fm.removeItem(at: destinationDirectory) }
        try fm.moveItem(at: staging, to: destinationDirectory)
        return destinationDirectory
    }
}
