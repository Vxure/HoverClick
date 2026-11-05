// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HoverClick",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HoverClickCore", targets: ["HoverClickCore"]),
        .executable(name: "HoverClick", targets: ["HoverClickApp"])
    ],
    targets: [
        .target(name: "HoverClickCore"),
        .executableTarget(name: "HoverClickApp", dependencies: ["HoverClickCore"]),
        .testTarget(name: "HoverClickCoreTests", dependencies: ["HoverClickCore"])
    ]
)
