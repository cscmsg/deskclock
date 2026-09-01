// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DeskClock",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "DeskClock",
            path: "Sources/DeskClock"
        )
    ]
)
