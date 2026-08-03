// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WealdRelayHost",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WealdRelayHost",
            path: "Sources/WealdRelayHost"
        )
    ]
)
