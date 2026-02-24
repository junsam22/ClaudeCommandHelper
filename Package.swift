// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeCommandHelper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeCommandHelper",
            path: "Sources"
        )
    ]
)
