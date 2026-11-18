// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MeterSage",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MeterSage", targets: ["MeterSage"])],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "MeterSage", dependencies: ["UsageCore"], exclude: ["Resources"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
        .testTarget(name: "MeterSageTests", dependencies: ["MeterSage", "UsageCore"])
    ]
)
