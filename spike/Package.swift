// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "nail-spike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "nail-spike", path: "Sources/nail-spike")
    ]
)
