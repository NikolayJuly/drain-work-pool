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
    dependencies: [
        .package(url: "https://github.com/vsanthanam/AnyAsyncSequence.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "WorkPoolDraning",
            dependencies: [
                .product(name: "AnyAsyncSequence", package: "AnyAsyncSequence")
            ]),
        .testTarget(
            name: "WorkPoolDraningTests",
            dependencies: ["WorkPoolDraning"]),
    ]
)
