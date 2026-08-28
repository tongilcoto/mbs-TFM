import Application
import Domain
import Fluent
import Foundation
import SQLKit
import Testing
import Vapor
@testable import App
import TestSupport
@testable import Persistence
@testable import Tenancy

/// Nivel 3 de la pirámide (§8.1): **Postgres real**, contenedor efímero.
///
/// Nunca SQLite: *schema*-por-tenant es exclusivo de Postgres y es justo lo que
/// hay que probar (D-01). Lo que se prueba aquí es el **mapeo y el enrutado**,
/// no las reglas — ésas ya las cubrieron los niveles 1 y 2 (Plan §5).
///
/// - Note: `docker compose up -d` antes de correrlos.
@Suite("Tenancy · §6.2 · el search_path aísla de verdad",
        .serialized,
        // Nivel 3/4: necesita Postgres. Sin él se omite en local y **falla**
        // en CI (`REQUIRE_DB`), para que verde nunca signifique "no probado".
        .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct TenancyIntegrationTests {

    /// Prefijo de *schema* propio de este target, para que los dos targets de
    /// integración no se pisen entre ellos.
    static let prefix = "test_"

    static func withApp(_ body: (Application) async throws -> Void) async throws {
        try await TestEnvironment.withApp(body)
    }

    static func provision(_ slug: String, federation: FederationCode, on app: Application) async throws {
        try await TestEnvironment.provisionClub(slug, federation: federation, schemaPrefix: prefix, on: app)
    }

    static func cleanUp(_ slugs: [String], on app: Application) async throws {
        try await TestEnvironment.dropClubs(slugs, schemaPrefix: prefix, on: app)
    }

    /// **La prueba no es que cada club vea sus filas**: es que el mismo `slug`
    /// —que lleva índice `UNIQUE`— convive en los dos *schemas*. Sin aislamiento,
    /// el segundo `INSERT` daría 409 (§3.5).
    @Test("las unicidades son por schema: un índice normal ya es único por club (§3.5)")
    func uniquenessIsPerTenant() async throws {
        try await Self.withApp { app in
            try await Self.cleanUp(["uniq-a", "uniq-b"], on: app)

            // El mismo slug en los dos clubes. Que no reviente **es** el resultado.
            try await Self.provision("uniq-a", federation: .rffm, on: app)
            try await Self.provision("uniq-b", federation: .fcf, on: app)

            let unitOfWork = FluentTenantUnitOfWork(controlDatabase: app.db(.control))
            let a = try await unitOfWork.withRepositories(
                actor: .init(clubSlug: try Slug("uniq-a"))
            ) { try await $0.clubs.current() }
            let b = try await unitOfWork.withRepositories(
                actor: .init(clubSlug: try Slug("uniq-b"))
            ) { try await $0.clubs.current() }

            #expect(a?.federation == .rffm)
            #expect(b?.federation == .fcf)
            #expect(a?.id != b?.id, "dos clubes distintos, dos filas distintas")

            try await Self.cleanUp(["uniq-a", "uniq-b"], on: app)
        }
    }

    /// El control negativo del spike, conservado a propósito (§6.2): `SET LOCAL`
    /// lo revierte Postgres al cerrar la transacción, **sin código de reseteo**.
    ///
    /// Si algún día falla, será porque el driver empezó a limpiar las conexiones
    /// — y entonces hay que revisar la conclusión de §6.2, no este test.
    @Test("SET LOCAL devuelve la conexión limpia al pool, sin código de reseteo (§6.2)")
    func searchPathDoesNotLeak() async throws {
        try await Self.withApp { app in
            try await Self.cleanUp(["leak"], on: app)
            try await Self.provision("leak", federation: .rffm, on: app)

            try await TenantRouting.withSearchPath("\(Self.prefix)leak", on: app.db(.control)) { database in
                let sql = database as! any SQLDatabase
                let inside = try await sql.raw("SHOW search_path").first(decodingColumn: "search_path", as: String.self)
                #expect(inside == "\(Self.prefix)leak", "dentro de la transacción manda el schema del club")
            }

            // Fuera del ámbito, sobre el **mismo pool**: la conexión no arrastra nada.
            let sql = app.db(.control) as! any SQLDatabase
            let after = try await sql.raw("SHOW search_path").first(decodingColumn: "search_path", as: String.self)
            #expect(after != "\(Self.prefix)leak", "la conexión volvió al pool contaminada — §6.2 ya no se sostiene")

            try await Self.cleanUp(["leak"], on: app)
        }
    }

    /// §4.7: el DDL de dominio aterriza en el *schema* del club y el del plano de
    /// control en `public`. Lo que lo consigue es el contraste de `space`.
    @Test("el DDL de dominio va al schema del club; el de control, a public (§4.7)")
    func migrationsLandInTheRightSchema() async throws {
        try await Self.withApp { app in
            try await Self.cleanUp(["ddl"], on: app)
            try await Self.provision("ddl", federation: .rffm, on: app)

            let sql = app.db(.control) as! any SQLDatabase
            func exists(_ table: String, in schema: String) async throws -> Bool {
                try await sql.raw("""
                    SELECT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema = \(bind: schema) AND table_name = \(bind: table)) AS present
                    """).first(decodingColumn: "present", as: Bool.self) ?? false
            }

            // Las tres tablas de dominio que hay hoy (F0 + F1). Cada fase suma
            // aquí las suyas: es el sitio donde se comprueba que una migración
            // nueva no se ha colado en `public` por olvidar el `space` (§4.7).
            for table in ["clubs", "seasons", "competitions"] {
                #expect(try await exists(table, in: "\(Self.prefix)ddl"), "falta \(table)")
                #expect(!(try await exists(table, in: "public")),
                        "`\(table)` se coló en public: revisa el `space` de su Record")
            }
            #expect(try await exists("_fluent_migrations", in: "\(Self.prefix)ddl"),
                    "el progreso se rastrea por club, no globalmente (§4.7)")
            #expect(try await exists("tenants", in: "public"))

            try await Self.cleanUp(["ddl"], on: app)
        }
    }
}

/// El ámbito de tenant reutiliza el que ya resolvió el middleware, en lugar de
/// volver a consultarlo (§6.1). Eso ahorra un `SELECT` por petición, pero abre
/// una pregunta que hay que contestar: **¿y si el ambiente y el actor no son el
/// mismo club?**
@Suite("TenantUnitOfWork · §6.1 · el ambiente y el actor tienen que coincidir",
        .serialized,
        // Nivel 3/4: necesita Postgres. Sin él se omite en local y **falla**
        // en CI (`REQUIRE_DB`), para que verde nunca signifique "no probado".
        .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct TenantScopeTests {

    /// Sin tenant ambiental —el caso del **job de ingesta** (§2.3-b), que no pasa
    /// por HTTP— se resuelve contra el plano de control, como siempre.
    @Test("sin tenant ambiental, se resuelve: es el camino de la ingesta")
    func resolvesWhenNoAmbientTenant() async throws {
        try await TenancyIntegrationTests.withApp { app in
            try await TenancyIntegrationTests.cleanUp(["scope-a"], on: app)
            try await TenancyIntegrationTests.provision("scope-a", federation: .rffm, on: app)

            let unitOfWork = FluentTenantUnitOfWork(controlDatabase: app.db(.control))
            let club = try await unitOfWork.withRepositories(
                actor: .init(clubSlug: try Slug("scope-a"))
            ) { try await $0.clubs.current() }

            #expect(club?.slug.value == "scope-a")
            try await TenancyIntegrationTests.cleanUp(["scope-a"], on: app)
        }
    }

    /// **La discrepancia se rechaza, no se resuelve a favor de ninguno.** Es el
    /// mismo criterio con que §6.1 trata el desacuerdo entre el `Host` y el
    /// *claim* del JWT: elegir uno sería confiar una decisión de aislamiento a un
    /// desempate implícito.
    ///
    /// Hoy no puede ocurrir —el `ActorContext` se construye **del** tenant
    /// ambiental—, y precisamente por eso el test importa: el día que el actor
    /// venga del *claim* firmado (§7.2) y el ambiente del `Host`, esta guarda es
    /// la que separa un 403 de una fuga entre clubes.
    @Test("si el ambiente dice un club y el actor otro, se rechaza (§6.1)")
    func rejectsMismatch() async throws {
        try await TenancyIntegrationTests.withApp { app in
            try await TenancyIntegrationTests.cleanUp(["scope-b", "scope-c"], on: app)
            try await TenancyIntegrationTests.provision("scope-b", federation: .rffm, on: app)
            try await TenancyIntegrationTests.provision("scope-c", federation: .fcf, on: app)

            let unitOfWork = FluentTenantUnitOfWork(controlDatabase: app.db(.control))
            let ambient = Tenant(slug: "scope-b", schemaName: "\(TenancyIntegrationTests.prefix)scope-b")

            await #expect(throws: TenancyError.self) {
                try await TenantContext.$current.withValue(ambient) {
                    // El actor dice `scope-c`; el ambiente, `scope-b`.
                    try await unitOfWork.withRepositories(
                        actor: .init(clubSlug: try Slug("scope-c"))
                    ) { try await $0.clubs.current() }
                }
            }

            try await TenancyIntegrationTests.cleanUp(["scope-b", "scope-c"], on: app)
        }
    }
}
