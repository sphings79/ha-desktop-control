// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ha-desktop-control",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HADesktopControl", targets: ["HADesktopControl"])
    ],
    targets: [
        .target(name: "DesktopControlCore"),
        .executableTarget(name: "HADesktopControl", dependencies: ["DesktopControlCore"]),
        .testTarget(name: "DesktopControlCoreTests", dependencies: ["DesktopControlCore"])
    ],
    swiftLanguageModes: [.v5]
)
