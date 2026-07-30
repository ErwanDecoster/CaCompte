// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CaCompteKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Catalog", targets: ["Catalog"]),
        .library(name: "Store", targets: ["Store"]),
        .library(name: "Sync", targets: ["Sync"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    targets: [
        .target(
            name: "Domain",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "Catalog",
            dependencies: ["Domain"],
            // Le dossier ne doit surtout pas s'appeler "Resources" : `codesign` plante dessus
            // dès qu'une vraie signature (Team ID) est utilisée sur ce macOS/Xcode (bug
            // reproduit hors projet, sur un bundle minimal fait à la main — voir README).
            resources: [.copy("GameDefinitions")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "Store",
            dependencies: ["Domain"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "Sync",
            dependencies: ["Domain"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "DesignSystem",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DomainTests",
            dependencies: ["Domain"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CatalogTests",
            dependencies: ["Catalog", "Domain"],
            resources: [.copy("GoldenResources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "StoreTests",
            dependencies: ["Store", "Domain"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SyncTests",
            dependencies: ["Sync", "Domain"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
