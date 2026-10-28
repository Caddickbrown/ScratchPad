// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScratchpadCore",
    platforms: [.iOS("18.0"), .macOS(.v14)],
    products: [
        .library(name: "ScratchpadCore", targets: ["ScratchpadCore"])
    ],
    targets: [
        .target(name: "ScratchpadCore", path: "Sources/ScratchpadCore"),
        .testTarget(name: "ScratchpadCoreTests", dependencies: ["ScratchpadCore"], path: "Tests/ScratchpadCoreTests")
    ]
)
