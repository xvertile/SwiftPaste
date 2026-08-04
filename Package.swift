// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftPaste",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SwiftPaste",
            path: "Sources/SwiftPaste"
        )
    ]
)
