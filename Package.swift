// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RPets",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RPets",
            path: "Sources/RPets",
            resources: [.copy("Pets")]
        ),
        .executableTarget(
            name: "RPetsTester",
            path: "Sources/RPetsTester"
        ),
        .executableTarget(
            name: "RPetsMCP",
            path: "Sources/RPetsMCP"
        )
    ]
)
