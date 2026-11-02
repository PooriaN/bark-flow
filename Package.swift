// swift-tools-version: 6.2
import PackageDescription
import Foundation

let local = ProcessInfo.processInfo.environment["BARK_FLUID_AUDIO_PATH"]
let dependency: Package.Dependency = local.map { .package(path: $0, traits: []) } ??
    .package(url: "https://github.com/FluidInference/FluidAudio.git",
             revision: "a00964e1aa8eff99c4bce80bc9c8ff2d4dd1568d", traits: [])

let package = Package(
    name: "BarkFlow", platforms: [.macOS(.v15)],
    dependencies: [dependency],
    targets: [
        .executableTarget(name: "BarkFlow", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
                          path: "Sources/BarkFlow"),
        .testTarget(name: "BarkFlowTests", dependencies: ["BarkFlow"])
    ], swiftLanguageModes: [.v5]
)
