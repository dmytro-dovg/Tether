// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Tether",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "Tether",
            targets: ["Tether"]
        ),
    ],
    targets: [
        .target(
            name: "Tether",
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
        ),
        .testTarget(
            name: "TetherTests",
            dependencies: ["Tether"],
            path: "TetherTests",
        )
    ]
)
