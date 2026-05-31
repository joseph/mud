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
        // swift-cmark is already in the graph transitively via swift-markdown.
        // Match swift-markdown's own URL and version range exactly so SwiftPM
        // unifies them to a single version (swift-markdown drives the choice).
        .package(
            url: "https://github.com/swiftlang/swift-cmark.git",
            from: "0.7.0"
        ),
    ],
    targets: [
        .target(
            name: "MudCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "cmark-gfm", package: "swift-cmark"),
            ],
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MudCoreTests",
            dependencies: ["MudCore"],
            path: "Tests"
        ),
    ]
)
