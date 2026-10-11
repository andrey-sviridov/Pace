// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PaceCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PaceCore", targets: ["PaceCore"]),
    ],
    targets: [
        .target(name: "PaceCore"),
        .testTarget(
            name: "PaceCoreTests",
            dependencies: ["PaceCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
