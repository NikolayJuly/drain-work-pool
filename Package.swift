// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "drain-work-pool",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "WorkPoolDraning",
            targets: ["WorkPoolDraning"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "WorkPoolDraning",
            dependencies: []),
        .testTarget(
            name: "WorkPoolDraningTests",
            dependencies: ["WorkPoolDraning"]),
    ]
)
