// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KopilkaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KopilkaCore", targets: ["KopilkaCore"]),
    ],
    targets: [
        .target(name: "KopilkaCore"),
        .testTarget(
            name: "KopilkaCoreTests",
            dependencies: ["KopilkaCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
