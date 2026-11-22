// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FTX1Status",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FTX1Core"),
        .executableTarget(name: "FTX1Status", dependencies: ["FTX1Core"]),
        .testTarget(name: "FTX1CoreTests", dependencies: ["FTX1Core"]),
    ]
)
