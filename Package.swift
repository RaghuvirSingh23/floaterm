// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Floaterm",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Floaterm", targets: ["Floaterm"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "Floaterm",
            dependencies: ["SwiftTerm"],
            path: "Sources/Floaterm",
            resources: [.process("../../Resources")]
        ),
        .testTarget(
            name: "FloatermTests",
            dependencies: ["Floaterm"],
            path: "Tests/FloatermTests"
        ),
    ]
)
