// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mach",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "mach",
            path: "Sources/mach",
            resources: [
                .copy("../../Resources/Info.plist")
            ]
        )
    ]
)
