// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TrafficLightsPlus",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TrafficLightsPlus",
            path: "Sources/TrafficLightsPlus"
        ),
        .testTarget(
            name: "TrafficLightsPlusTests",
            dependencies: ["TrafficLightsPlus"],
            path: "Tests/TrafficLightsPlusTests"
        )
    ]
)
