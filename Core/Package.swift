// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MudCore", targets: ["MudCore"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-markdown.git",
            from: "0.5.0"
        ),
    ],
    targets: [
        .target(
            name: "MudCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/Core",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MudCoreTests",
            dependencies: ["MudCore"],
            path: "Tests/Core"
        ),
    ]
)
