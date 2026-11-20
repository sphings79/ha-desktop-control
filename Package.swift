// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ha-desktop-control",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HADesktopControl", targets: ["HADesktopControl"])
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server-community/mqtt-nio.git", from: "2.13.0")
    ],
    targets: [
        .target(name: "DesktopControlCore"),
        .executableTarget(
            name: "HADesktopControl",
            dependencies: [
                "DesktopControlCore",
                .product(name: "MQTTNIO", package: "mqtt-nio")
            ]),
        .testTarget(name: "DesktopControlCoreTests", dependencies: ["DesktopControlCore"])
    ],
    swiftLanguageModes: [.v5]
)
