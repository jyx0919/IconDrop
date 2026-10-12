// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IconDrop",
    platforms: [.macOS(.v14)],
    products: [.library(name: "IconDropCore", targets: ["IconDropCore"])],
    targets: [
        .target(name: "IconDropCore"),
        .testTarget(name: "IconDropCoreTests", dependencies: ["IconDropCore"]),
    ]
)
