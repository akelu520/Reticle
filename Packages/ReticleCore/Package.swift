// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ReticleCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ReticleCore", targets: ["ReticleCore"]),
    ],
    targets: [
        // Stitching and rendering are hot loops; keep them optimized in Debug builds too,
        // otherwise live scroll capture falls behind while debugging.
        .target(name: "ReticleCore", swiftSettings: [.unsafeFlags(["-O"], .when(configuration: .debug))]),
        .testTarget(name: "ReticleCoreTests", dependencies: ["ReticleCore"]),
    ]
)
