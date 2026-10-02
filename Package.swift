// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MCClose",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MCCloseCore", path: "Sources/MCCloseCore"),
        .executableTarget(name: "MCClose", dependencies: ["MCCloseCore"], path: "Sources/MCClose"),
        .testTarget(name: "MCCloseTests", dependencies: ["MCCloseCore"], path: "Tests/MCCloseTests"),
    ]
)
