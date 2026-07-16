// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Rhizome",
    platforms: [
        .iOS("26.0"),   // stamps the binary's LC_BUILD_VERSION sdk = 26 → Liquid Glass tab bar
        .macOS(.v15),
    ],
    products: [
        // The main app.
        .library(
            name: "Rhizome",
            targets: ["Rhizome"]
        ),
    ],
    targets: [
        // Shared config + API client.
        .target(
            name: "RhizomeKit"
        ),
        .target(
            name: "Rhizome",
            dependencies: ["RhizomeKit"],
            resources: [.process("Resources")]
        ),
    ]
)
