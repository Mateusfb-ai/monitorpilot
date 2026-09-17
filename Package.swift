// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MonitorPilot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MonitorPilot",
            path: "Sources/MonitorPilot"
        ),
        .testTarget(
            name: "MonitorPilotTests",
            dependencies: ["MonitorPilot"],
            path: "Tests/MonitorPilotTests"
        ),
    ]
)
