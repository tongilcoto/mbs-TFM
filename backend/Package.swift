// swift-tools-version:6.2
import PackageDescription

// ─────────────────────────────────────────────────────────────────────────────
// Un target por capa (LLD §2.2). El grafo de dependencias de abajo ES la Regla
// de dependencia: `Domain` no depende de nada, así que **no puede** importar
// Vapor ni Fluent aunque alguien lo intente — no compila. Ese es todo el punto
// de dividir el paquete así en vez de usar carpetas.
//
//   Run ─► App ─┬─► HTTPAdapter ─┬─► APIContract   (tipos generados del spec)
//               │                └─► Application
//               ├─► Persistence ────► Application
//               ├─► Tenancy
//               └─► Application ────► Domain
//
// Referencias `§x` → docs/API_y_BBDD LLD-001.md
// Referencias `D-nn` → docs/API_y_BBDD LLD-Anexo-Decisiones-Disenho-001.md
// ─────────────────────────────────────────────────────────────────────────────

/// Ajustes comunes a todos los targets.
///
/// **Swift 6 en todos, sin válvula de escape** (Plan de desarrollo §6): si Fluent
/// pelea con la concurrencia estricta se resuelve con aislamiento correcto, no
/// bajando el modo de lenguaje.
///
/// Lo que **no** se adopta y merece explicación: `defaultIsolation: MainActor`.
/// Es la recomendación moderna para *apps* — en un backend serializaría el
/// servidor entero en un actor.
let commonSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),        // SE-0335: `any` explícito
    .enableUpcomingFeature("MemberImportVisibility"), // SE-0444: sin imports transitivos
    .enableUpcomingFeature("InferIsolatedConformances"), // SE-0470
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"), // SE-0461
]

let package = Package(
    name: "ClubBackend",
    platforms: [.macOS(.v15)],
    products: [
        // SwiftPM omite del grafo de build los targets que nadie consume, así que
        // `swift build --target X` sobre una hoja responde "no target named". Declarar
        // las capas como productos las hace construibles y testeables por separado,
        // que es justo como se trabaja una fase del plan (una capa cada vez).
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Application", targets: ["Application"]),
        .library(name: "APIContract", targets: ["APIContract"]),
        .executable(name: "Run", targets: ["Run"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.122.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.12.0"),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.13.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.12.0"),
        .package(url: "https://github.com/vapor/swift-openapi-vapor.git", from: "1.1.0"),
    ],
    targets: [
        // ── Núcleo ────────────────────────────────────────────────────────────
        // Sin dependencias, y es deliberado: es lo que hace cumplir §2.2.
        .target(
            name: "Domain",
            swiftSettings: commonSwiftSettings
        ),

        // Casos de uso y puertos (§4.3). Solo conoce el Dominio.
        .target(
            name: "Application",
            dependencies: ["Domain"],
            swiftSettings: commonSwiftSettings
        ),

        // ── Contrato ──────────────────────────────────────────────────────────
        // Tipos y `APIProtocol` generados del spec por el plugin (D-65). El
        // fichero vive aquí dentro porque es donde el plugin lo espera.
        .target(
            name: "APIContract",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            ],
            swiftSettings: commonSwiftSettings,
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),

        // ── Adaptadores ───────────────────────────────────────────────────────
        // Primario (driving): traduce DTO generado ↔ dominio e invoca casos de uso.
        .target(
            name: "HTTPAdapter",
            dependencies: [
                "APIContract",
                "Application",
                "Tenancy",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIVapor", package: "swift-openapi-vapor"),
                .product(name: "Vapor", package: "vapor"),
            ],
            swiftSettings: commonSwiftSettings
        ),

        // Secundario (driven): implementa los puertos de salida con Fluent.
        .target(
            name: "Persistence",
            dependencies: [
                "Application",
                "Domain",
                "Tenancy",
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
            ],
            swiftSettings: commonSwiftSettings
        ),

        // ── Infraestructura ───────────────────────────────────────────────────
        // Plano de control de tenancy (§6). No es dominio: `public.tenants` es
        // infraestructura y no debe confundirse con la entidad `Club` (§4.7).
        .target(
            name: "Tenancy",
            dependencies: [
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "Vapor", package: "vapor"),
            ],
            swiftSettings: commonSwiftSettings
        ),

        // Raíz de composición: es el único sitio donde se cablean las capas.
        .target(
            name: "App",
            dependencies: [
                "APIContract",
                "Application",
                "Domain",
                "HTTPAdapter",
                "Persistence",
                "Tenancy",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
            ],
            swiftSettings: commonSwiftSettings
        ),

        .executableTarget(
            name: "Run",
            dependencies: ["App"],
            swiftSettings: commonSwiftSettings
        ),

        // ── Tests, uno por nivel de la pirámide (§8.1) ─────────────────────────
        // Niveles 1 y 2: cero I/O, y por eso son los que se ejecutan siempre.
        .testTarget(
            name: "DomainTests",
            dependencies: ["Domain"],
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "ApplicationTests",
            dependencies: ["Application", "Domain"],
            swiftSettings: commonSwiftSettings
        ),
        // Niveles 3 y 4: Postgres real en contenedor efímero, nunca SQLite (§8.1).
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", "Tenancy", "App"],
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "APITests",
            dependencies: [
                "App",
                "APIContract",
                .product(name: "VaporTesting", package: "vapor"),
            ],
            swiftSettings: commonSwiftSettings
        ),
    ]
)
