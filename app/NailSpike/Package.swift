// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NailSpike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "NailSpike", path: "Sources/NailSpike"),
        .testTarget(name: "NailSpikeTests", dependencies: ["NailSpike"])
    ]
)
