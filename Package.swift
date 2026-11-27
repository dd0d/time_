// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Rhythm",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Rhythm", targets: ["Rhythm"])],
    targets: [
        .target(name: "RhythmCore"),
        .executableTarget(name: "Rhythm", dependencies: ["RhythmCore"]),
        .testTarget(name: "RhythmCoreTests", dependencies: ["RhythmCore"]),
        .testTarget(name: "RhythmAppTests", dependencies: ["Rhythm", "RhythmCore"])
    ],
    swiftLanguageModes: [.v5]
)
