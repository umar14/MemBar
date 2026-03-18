// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MemBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MemBar",
            path: "Sources/MemBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
            ]
        )
    ]
)
