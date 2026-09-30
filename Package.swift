// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MCClose",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MCClose", path: "Sources/MCClose")
    ]
)
