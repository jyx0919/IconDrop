// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IconDrop",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "IconDropCore", targets: ["IconDropCore"]),
        .executable(name: "IconDropApp", targets: ["IconDropApp"]),
    ],
    targets: [
        .target(name: "IconDropCore"),
        .executableTarget(name: "IconDropApp", dependencies: ["IconDropCore"]),
        .testTarget(name: "IconDropCoreTests", dependencies: ["IconDropCore"]),
    ]
)
