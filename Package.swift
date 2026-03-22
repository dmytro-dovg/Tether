// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Tether",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "Tether",
            targets: ["Tether"],
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.63.2"),
    ],
    targets: [
        .target(
            name: "Tether",
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")],
        ),
        .testTarget(
            name: "TetherTests",
            dependencies: ["Tether"],
            path: "TetherTests",
        )
    ]
)
