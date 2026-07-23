// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Core",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MudCore", targets: ["MudCore"]),
    ],
    dependencies: [
        // The single Markdown parser. Mud links cmark-gfm directly; the
        // swift-markdown wrapper it used to render through was removed at the
        // single-parser cutover (see
        // Doc/Plans/Archive/2026-07-single-parser-rendering.md). Pinned to
        // 0.8.0 (via Package.resolved), the version `CMarkDocument`'s
        // hard-coded parse options are calibrated to.
        .package(
            url: "https://github.com/swiftlang/swift-cmark.git",
            from: "0.7.0"
        ),
    ],
    targets: [
        .target(
            name: "MudCore",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
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
