// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "facturx-check",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "facturx-check", targets: ["facturx-check"]),
        .library(name: "FacturXKit", targets: ["FacturXKit"])
    ],
    targets: [
        .target(name: "FacturXKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "facturx-check", dependencies: ["FacturXKit"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "FacturXKitTests", dependencies: ["FacturXKit"],
                    swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
