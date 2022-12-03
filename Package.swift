// swift-tools-version: 5.7

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
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "WorkPoolDraning",
            dependencies: [
                .product(name: "DequeModule", package: "swift-collections")
            ]),
        .testTarget(
            name: "WorkPoolDraningTests",
            dependencies: ["WorkPoolDraning"]),
    ]
)
