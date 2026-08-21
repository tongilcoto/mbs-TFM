// swift-tools-version:6.0
import PackageDescription

// Spike desechable — valida la hipótesis de multi-tenancy del LLD §4.6/§4.7/§6.
// NO es el esqueleto del backend: aquí no hay capas (§2.2), solo lo mínimo para
// confirmar o desmentir tres suposiciones sobre Fluent + Postgres.
let package = Package(
    name: "TenancySpike",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.12.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.10.0"),
    ],
    targets: [
        .target(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Run",
            dependencies: [.target(name: "App")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "XCTVapor", package: "vapor"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
