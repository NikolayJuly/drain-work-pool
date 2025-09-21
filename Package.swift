// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "drain-work-pool",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "WorkPoolDraining",
            targets: ["WorkPoolDraining"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "WorkPoolDraining",
            dependencies: []),
        .testTarget(
            name: "WorkPoolDrainingTests",
            dependencies: ["WorkPoolDraining"]),
    ]
)
