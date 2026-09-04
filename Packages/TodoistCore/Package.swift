// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TodoistCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "TodoistCore", targets: ["TodoistCore"])],
    targets: [
        .target(name: "TodoistCore"),
        .testTarget(name: "TodoistCoreTests", dependencies: ["TodoistCore"]),
    ]
)
