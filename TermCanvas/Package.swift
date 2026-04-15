// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TermCanvas",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "TermCanvas",
            targets: ["TermCanvas"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "TermCanvas",
            path: "Sources",
            resources: [
                .copy("Resources/Terminal"),
            ]
        ),
        .testTarget(
            name: "TermCanvasTests",
            dependencies: ["TermCanvas"]
        ),
    ]
)
