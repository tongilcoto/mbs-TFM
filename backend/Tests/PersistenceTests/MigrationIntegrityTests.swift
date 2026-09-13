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

/// Nivel 3 (§8.1): **Postgres real**. Lo que se prueba aquí es lo que el bloque
/// `A-5` del plan de auditoría midió a mano y no medía nadie (H-38).
///
/// Dos garantías, y la segunda es la que el bloque venía a buscar:
///
/// - **el `revert` deshace de verdad**, hasta el punto de que volver a migrar
///   deja el *schema* exactamente como estaba;
/// - **dos clubes migrados por caminos distintos quedan iguales**, que es lo que
///   hace que el esquema de un club no dependa de cuándo se dio de alta.
///
/// - Note: `docker compose up -d` antes de correrlos.
@Suite("Migraciones · §4.6/§4.7 · el revert deshace y los caminos convergen",
        .serialized,
        .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct MigrationIntegrityTests {

    static let prefix = "test_mig_"

    static func withApp(_ body: (Application) async throws -> Void) async throws {
        try await TestEnvironment.withApp(body)
    }

    static func provision(_ slug: String, on app: Application) async throws -> String {
        try await TestEnvironment.provisionClub(
            slug, federation: .rffm, schemaPrefix: prefix, on: app)
    }

    static func cleanUp(_ slugs: [String], on app: Application) async throws {
        try await TestEnvironment.dropClubs(slugs, schemaPrefix: prefix, on: app)
    }

    /// **El inventario del esquema, leído del catálogo y no del `pg_dump`.**
    ///
    /// `pg_dump` es un binario del contenedor y no se puede invocar desde el
    /// proceso de test, así que la comparación va por `pg_class`/`pg_constraint`,
    /// que es además la segunda vía con la que `A-5` corroboró el `diff`. Se
    /// normaliza el nombre del *schema* —es lo único que **debe** diferir— y se
    /// excluye `_fluent_migrations`, que es tabla de control y no esquema de
    /// dominio: sus filas cuentan lotes, y los lotes son justamente lo que
    /// distingue a un camino del otro.
    static func inventory(of schema: String, on app: Application) async throws -> [String] {
        let sql = app.db(.control) as! any SQLDatabase

        let relations = try await sql.raw("""
            SELECT c.relkind::text || ' ' || c.relname AS line
            FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = \(bind: schema)
              -- Y sus índices, que **no** empiezan por el nombre de la tabla:
              -- uno se llama `uq:_fluent_migrations.name`. `position` en vez de
              -- `LIKE` para no pelearse con el escape del guión bajo.
              AND position('_fluent_migrations' in c.relname) = 0
            """).all(decodingColumn: "line", as: String.self)

        let constraints = try await sql.raw("""
            SELECT con.contype::text || ' ' || con.conname || ' ' ||
                   pg_get_constraintdef(con.oid) AS line
            FROM pg_constraint con JOIN pg_namespace n ON n.oid = con.connamespace
            WHERE n.nspname = \(bind: schema) AND con.conname NOT LIKE '%fluent%'
            """).all(decodingColumn: "line", as: String.self)

        let indexes = try await sql.raw("""
            SELECT indexdef AS line FROM pg_indexes
            WHERE schemaname = \(bind: schema) AND tablename <> '_fluent_migrations'
            """).all(decodingColumn: "line", as: String.self)

        return (relations + constraints + indexes)
            .map { $0.replacingOccurrences(of: schema, with: "TENANT") }
            .sorted()
    }

    /// Cuántos lotes lleva aplicados un *schema*. Es lo que distingue un club
    /// migrado de una vez de uno migrado por fases: el esquema no lo dice, pero
    /// `_fluent_migrations` sí (§4.7).
    static func batches(of schema: String, on app: Application) async throws -> Int {
        let sql = app.db(.control) as! any SQLDatabase
        return try await sql.raw("""
            SELECT count(DISTINCT batch) AS n FROM \(ident: schema).\(ident: "_fluent_migrations")
            """).first(decodingColumn: "n", as: Int.self) ?? 0
    }

    /// H-30/H-38: **el `revert` deshace de verdad**, y la prueba no es que no
    /// falle: es que volver a migrar deja el esquema **exactamente** como estaba.
    ///
    /// Un `revert` que se dejara un índice, un `CHECK` o una tabla se vería por
    /// dos sitios: el inventario intermedio no quedaría vacío, y el `prepare`
    /// siguiente reventaría con `42P07` — que es el error que el test de arriba
    /// provoca a propósito, así que está demostrado que ese fallo se ve.
    @Test("el revert deshace de verdad: volver a migrar deja el mismo esquema (H-30)")
    func revertIsAFaithfulRoundTrip() async throws {
        try await Self.withApp { app in
            try await Self.cleanUp(["rt"], on: app)
            let schema = try await Self.provision("rt", on: app)

            let before = try await Self.inventory(of: schema, on: app)
            #expect(before.count > 50, "el inventario está vacío: la comparación no diría nada")

            // **Dos anclas absolutas, no solo la comparación relativa.** Sin
            // ellas el test diría "los dos lados son iguales" y no notaría que
            // los dos han perdido lo mismo: es justo la forma de fallar de los
            // ayudantes de SQL crudo, que se saltaban su trabajo en silencio
            // cuando la base no era `SQLDatabase` (H-35). Lo que se ancla es lo
            // que Fluent **no** sabe expresar y por tanto va por `sql.raw`
            // (§4.6): los `CHECK` derivados de `D-02` y el `NULLS NOT DISTINCT`
            // de la clave de `Team` (§3.5).
            #expect(before.filter { $0.hasPrefix("c chk_") }.count == 10,
                    "faltan CHECK: \(before.filter { $0.hasPrefix("c chk_") })")
            #expect(before.contains { $0.contains("uq_teams_identity") && $0.contains("NULLS NOT DISTINCT") },
                    "la clave de Team perdió el NULLS NOT DISTINCT: acepta dos «Cadete A» propios (§3.5)")

            try await MigrateTenantsCommand.revert(schema: schema, on: app)

            let afterRevert = try await Self.inventory(of: schema, on: app)
            #expect(afterRevert.isEmpty,
                    "el revert dejó algo en pie: \(afterRevert.joined(separator: " · "))")
            #expect(try await Self.batches(of: schema, on: app) == 0,
                    "la tabla de control conserva lotes: el schema no es reejecutable")

            try await MigrateTenantsCommand.migrate(schema: schema, on: app)

            #expect(try await Self.inventory(of: schema, on: app) == before,
                    "ida y vuelta no es la identidad")

            try await Self.cleanUp(["rt"], on: app)
        }
    }

    /// H-30, y es la pregunta con la que `A-5` abría: **¿depende el esquema de un
    /// club de cuándo se dio de alta?**
    ///
    /// Los dos caminos de §4.7: `provision-tenant` pasa el juego **completo** a
    /// un *schema* nuevo; `migrate-tenants` aplica **solo las que faltan** a uno
    /// viejo. El tenant de trabajo llegó a las ocho migraciones en **tres lotes
    /// de tres días** (F0, F1, F5), y aquí eso se reproduce con un prefijo de la
    /// lista — sin el cual el test compararía dos altas limpias y no diría nada,
    /// que es por lo que la aserción de los **dos lotes** no es decorativa.
    @Test("dos clubes migrados por caminos distintos convergen (H-30, §4.7)")
    func bothPathsConvergeOnTheSameSchema() async throws {
        try await Self.withApp { app in
            try await Self.cleanUp(["path-a", "path-b"], on: app)

            // Camino A: alta limpia, juego completo de una vez.
            let a = try await Self.provision("path-a", on: app)

            // Camino B: primero las tres de F0/F1, y **después** el resto —que
            // en la lista van intercaladas *antes* de `CreateCompetition`, así
            // que se aplican en un orden distinto del de registro.
            let b = "\(Self.prefix)path-b"
            let sql = app.db(.control) as! any SQLDatabase
            try await sql.raw("CREATE SCHEMA IF NOT EXISTS \(ident: b)").run()
            try await MigrateTenantsCommand.migrate(
                schema: b, migrations: Array(TenantMigrations.all().prefix(2)), on: app)
            try await MigrateTenantsCommand.migrate(schema: b, on: app)

            #expect(try await Self.batches(of: b, on: app) == 2,
                    "el camino B no fue incremental: el test compara dos altas limpias")
            #expect(try await Self.batches(of: a, on: app) == 1)

            let inventoryA = try await Self.inventory(of: a, on: app)
            let inventoryB = try await Self.inventory(of: b, on: app)
            #expect(inventoryA == inventoryB,
                    "el esquema de un club depende de cuándo se dio de alta (§4.7)")

            try await sql.raw("DROP SCHEMA IF EXISTS \(ident: b) CASCADE").run()
            try await Self.cleanUp(["path-a", "path-b"], on: app)
        }
    }

    /// H-33: el recorrido **se para** cuando un club falla —eso ya lo hacía, y es
    /// lo que `D-86` prescribe para un fallo que no deja constancia— pero antes
    /// se paraba por un error crudo del driver que no nombraba al club.
    ///
    /// El saboteo es el mismo con el que `A-5` lo midió: revertir un tenant y
    /// dejarle una tabla que choque con la primera migración del juego.
    @Test("un fallo de migración dice de qué club fue (H-33, D-86, §9.3)")
    func aMigrationFailureNamesItsTenant() async throws {
        try await Self.withApp { app in
            try await Self.cleanUp(["fail"], on: app)
            let schema = try await Self.provision("fail", on: app)

            // Punto de partida: un tenant con migraciones pendientes. Revertir es
            // la vía honesta de conseguirlo, y ejercita el `revert` de paso.
            try await MigrateTenantsCommand.revert(schema: schema, on: app)

            let sql = app.db(.control) as! any SQLDatabase
            try await sql.raw(
                "CREATE TABLE \(ident: schema).\(ident: "clubs") (\(ident: "x")  INT)"
            ).run()

            let tenant = TenantRecord(slug: "fail", schemaName: schema)
            let failure = await #expect(throws: TenantMigrationFailure.self) {
                try await MigrateTenantsCommand.apply(to: tenant, revert: false, on: app)
            }

            #expect(failure?.slug == "fail")
            #expect(failure?.schemaName == schema)
            // El motivo verdadero viaja dentro, y legible: un `PSQLError`
            // interpolado a secas no dice nada (lo aprendió F6 en `IngestionRun`).
            #expect(failure?.description.contains("'fail'") == true,
                    "el fallo no nombra al club: a 50 clubes no se sabe dónde paró")
            #expect(failure?.description.contains("42P07") == true,
                    "el motivo verdadero no sobrevive al envoltorio")

            try await Self.cleanUp(["fail"], on: app)
        }
    }
}

/// Nivel 1: lógica pura, **sin base de datos** — y por eso fuera de la suite de
/// arriba, que está condicionada a que Postgres esté levantado.
@Suite("migrate-tenants · la bandera que destruye datos pide permiso (H-32)")
struct RevertAuthorizationTests {

    /// El caso que `A-5` midió: `--revert` borró las tablas de un club en un
    /// comando y sin una sola pregunta, actuando sobre **todos** los de
    /// `public.tenants` si se omite `-t`.
    @Test("--revert sin --yes no llega a la base")
    func revertRequiresConfirmation() throws {
        #expect(throws: MigrateTenantsCommand.RevertNotConfirmed.self) {
            try MigrateTenantsCommand.authorizeRevert(revert: true, confirmed: false)
        }
    }

    /// El reverso, que es el que protege de una guarda pasada de celosa: migrar
    /// —el uso normal, el del cron y el de cada alta— **no** pide nada.
    @Test("migrar no pide confirmación: la guarda es solo del camino destructivo")
    func migratingNeedsNothing() throws {
        #expect(throws: Never.self) {
            try MigrateTenantsCommand.authorizeRevert(revert: false, confirmed: false)
        }
        #expect(throws: Never.self) {
            try MigrateTenantsCommand.authorizeRevert(revert: true, confirmed: true)
        }
    }
}
