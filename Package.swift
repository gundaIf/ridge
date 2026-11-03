// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ridge",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CMultitouch", path: "Sources/CMultitouch"),
        .executableTarget(name: "Ridge", dependencies: ["CMultitouch"], path: "Sources/Ridge")
    ]
)
