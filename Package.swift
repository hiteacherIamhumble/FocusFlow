// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "FocusFlow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "FocusFlowCore", targets: ["FocusFlowCore"]),
        .executable(name: "FocusFlow", targets: ["FocusFlowApp"])
    ],
    targets: [
        .target(
            name: "FocusFlowCore",
            path: "Sources/FocusFlowCore"
        ),
        .executableTarget(
            name: "FocusFlowApp",
            dependencies: ["FocusFlowCore"],
            path: "Sources/FocusFlowApp"
        ),
        .testTarget(
            name: "FocusFlowCoreTests",
            dependencies: ["FocusFlowCore"],
            path: "Tests/FocusFlowCoreTests"
        )
    ]
)
