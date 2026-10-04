// swift-tools-version:6.2
import PackageDescription

// ─────────────────────────────────────────────────────────────────────────────
// El censo del contrato (`A-15`·punto 7, H-72).
//
// Los dos recuentos que sostienen el cierre de F10-ter y de A-14 —qué códigos
// `Problem` nombra algún test, y qué campos de las respuestas del contrato— se
// hicieron a mano con `grep` y `ruby -ryaml` y no se guardaron: F10-ter contó
// 52 campos, A-14 contó 61, y nadie puede saber por qué. Esto es el método,
// escrito y versionado.
//
// **Paquete aparte, por lo mismo que `Tools/Mutate`**: sus tests miden el
// instrumento, no el producto, y no deben mover el recuento de la batería.
//
//   CensusCore — lo que cuenta: códigos, campos, huecos conocidos. Puro.
//   census     — lo que lee: ficheros de `Sources/`, `Tests/` y el *spec*.
//
// Uso y límites: Tools/Census/README.md.
// ─────────────────────────────────────────────────────────────────────────────

let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "Census",
    platforms: [.macOS(.v15)],
    dependencies: [
        // La misma que fija `backend/Package.resolved`.
        .package(url: "https://github.com/jpsim/Yams", exact: "6.2.2"),
    ],
    targets: [
        .target(name: "CensusCore", swiftSettings: settings),
        .executableTarget(
            name: "census",
            dependencies: ["CensusCore", .product(name: "Yams", package: "Yams")],
            swiftSettings: settings),
        .testTarget(
            name: "CensusCoreTests",
            dependencies: ["CensusCore"],
            swiftSettings: settings),
    ]
)
