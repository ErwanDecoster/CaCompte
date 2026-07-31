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
    // Doc utilisateur P9 — remontée : après cinq correctifs BLE distincts, tous réels et
    // vérifiés, sans que la connexion ne s'établisse jamais entre les deux appareils, la
    // synchronisation live est déplacée sur Supabase Realtime plutôt que sur du Wi-Fi/BLE fait
    // maison. Exception explicite et assumée à l'ADR-0012 (« aucune dépendance tierce ») — la
    // fiabilité de connexion/reconnexion est déléguée à un SDK websocket mature plutôt qu'à du
    // code réseau/Bluetooth maison qui s'est montré structurellement peu fiable en conditions
    // réelles.
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
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
            dependencies: [
                "Domain",
                .product(name: "Supabase", package: "supabase-swift"),
            ],
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
