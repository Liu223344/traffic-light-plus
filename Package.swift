// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TrafficLightsPlus",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.2"
        )
    ],
    targets: [
        .executableTarget(
            name: "TrafficLightsPlus",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/TrafficLightsPlus",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "TrafficLightsPlusTests",
            dependencies: ["TrafficLightsPlus"],
            path: "Tests/TrafficLightsPlusTests"
        )
    ]
)
