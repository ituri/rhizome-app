// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Rhizome",
    platforms: [
        .iOS(.v18),
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
            dependencies: ["RhizomeKit"]
        ),
        .target(
            name: "RhizomeShare",
            dependencies: ["RhizomeKit"]
        ),
    ]
)
