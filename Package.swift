// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AutoSuggestApp",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "AutoSuggestApp",
            targets: ["AutoSuggestApp"]
        ),
        .executable(
            name: "AutoSuggestRunner",
            targets: ["AutoSuggestRunner"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/huggingface/swift-transformers", from: "0.1.24"), // 0.1.24 verified against this codebase; test before crossing 0.2.0
    ],
    targets: [
        .target(
            name: "AutoSuggestApp",
            dependencies: [
                .product(name: "Transformers", package: "swift-transformers"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .executableTarget(
            name: "AutoSuggestRunner",
            dependencies: ["AutoSuggestApp"]
        ),
        .testTarget(
            name: "AutoSuggestAppTests",
            dependencies: ["AutoSuggestApp"]
        ),
    ]
)
