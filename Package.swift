// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Floaterm",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "Floaterm",
            targets: ["Floaterm"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "Floaterm",
            path: "Sources",
            resources: [
                .copy("Resources/Terminal"),
            ]
        ),
        .testTarget(
            name: "FloatermTests",
            dependencies: ["Floaterm"],
            path: "Tests/FloatermTests"
        ),
    ]
)
