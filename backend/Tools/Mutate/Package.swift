// swift-tools-version:6.2
import PackageDescription

// ─────────────────────────────────────────────────────────────────────────────
// El instrumento de mutación del backend (`A-15`·H-52).
//
// **Paquete aparte, y a propósito.** Sus tests miden el instrumento, no el
// producto: si vivieran en `ClubBackend` cambiarían el recuento de la batería
// (`REQUIRE_DB=1 swift test`) cada vez que se tocara el guion, y el recuento es
// la cifra que cierra cada fase.
//
//   MutateCore  — lo que decide: catálogo, aplicar, veredicto, informe. Puro.
//   mutate      — lo que ejecuta: ficheros, `swift build`, `swift test`.
//
// Uso y reglas: Tools/Mutate/README.md.
// ─────────────────────────────────────────────────────────────────────────────

let settings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "Mutate",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "MutateCore", swiftSettings: settings),
        .executableTarget(
            name: "mutate",
            dependencies: ["MutateCore"],
            swiftSettings: settings),
        .testTarget(
            name: "MutateCoreTests",
            dependencies: ["MutateCore"],
            swiftSettings: settings),
    ]
)
