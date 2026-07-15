// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Rhizome",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // An xtool project contains exactly one library product, representing the main app.
        .library(
            name: "Rhizome",
            targets: ["Rhizome"]
        ),
    ],
    targets: [
        .target(
            name: "Rhizome"
        ),
    ]
)
