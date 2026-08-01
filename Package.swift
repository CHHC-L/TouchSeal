// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TouchSeal",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "touchseal",
            targets: ["TouchSeal"]
        )
    ],
    targets: [
        .executableTarget(
            name: "TouchSeal"
        ),
        .testTarget(
            name: "TouchSealTests",
            dependencies: ["TouchSeal"]
        )
    ]
)
