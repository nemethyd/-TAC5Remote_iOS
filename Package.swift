// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TAC5Core",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "TAC5Core", targets: ["TAC5Core"])
    ],
    targets: [
        .target(name: "TAC5Core"),
        .testTarget(name: "TAC5CoreTests", dependencies: ["TAC5Core"])
    ]
)
