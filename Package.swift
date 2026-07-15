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
        // The Share Extension (native quick-capture).
        .library(
            name: "RhizomeShare",
            targets: ["RhizomeShare"]
        ),
    ],
    targets: [
        // Shared config + capture client, used by both the app and the extension.
        .target(
            name: "RhizomeKit"
        ),
        .target(
            name: "Rhizome",
            dependencies: ["RhizomeKit"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "RhizomeShare",
            dependencies: ["RhizomeKit"]
        ),
    ]
)
