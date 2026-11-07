// swift-tools-version: 5.9
import PackageDescription

// Run scripts/build-core.sh once first: the xcframework is a build product, not in git.
let package = Package(
    name: "ScratchpadCore",
    platforms: [.iOS("18.0"), .macOS("15.0")],
    products: [
        .library(name: "ScratchpadCore", targets: ["ScratchpadCore"])
    ],
    targets: [
        .binaryTarget(name: "ScratchpadCoreFFI", path: "Frameworks/ScratchpadCoreFFI.xcframework"),
        .target(name: "ScratchpadFFI", dependencies: ["ScratchpadCoreFFI"], path: "Sources/ScratchpadFFI"),
        .target(name: "ScratchpadCore", dependencies: ["ScratchpadFFI"], path: "Sources/ScratchpadCore"),
        .executableTarget(name: "core-check", dependencies: ["ScratchpadCore"], path: "Sources/core-check"),
        .testTarget(name: "ScratchpadCoreTests", dependencies: ["ScratchpadCore"], path: "Tests/ScratchpadCoreTests")
    ]
)
