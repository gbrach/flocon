// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Flocon",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Flocon", resources: [.copy("Rendering/Shaders.metal")]),
        .testTarget(name: "FloconTests", dependencies: ["Flocon"]),
    ]
)
