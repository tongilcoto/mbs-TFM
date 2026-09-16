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

    /// **F8: el `CHECK` de un enumerado no se mantiene solo, y esto es lo que lo
    /// vigila.**
    ///
    /// # El defecto que este test existe para cazar, y que ya ocurrió
    ///
    /// `D-02` dice que el `CHECK` de un enumerado **se deriva y no se teclea**, y
    /// `sqlValueList` lo cumple. De ahí se concluyó —y quedó escrito en
    /// `AddStandingsToIngestionRun`— que *"el caso que F8 añada lo hereda sin
    /// tocar SQL"*. **Es falso.** La derivación ocurre **una sola vez**, cuando la
    /// migración corre, y lo que queda en el *schema* es el texto de aquel día.
    /// Medido en `club_atleti` antes de arreglarlo:
    ///
    /// ```
    /// chk_ingestion_runs_kind → CHECK (kind = ANY (ARRAY['calendar','standings']))
    /// ```
    ///
    /// Es `D-90` un piso más abajo: **derivado no significa vivo**.
    ///
    /// # Por qué no bastaba el inventario de constraints
    ///
    /// Porque **cuenta**, y este fallo no cambia la cuenta: `chk_ingestion_runs_kind`
    /// sigue siendo una constraint antes y después de añadir el caso. El
    /// inventario habría seguido en verde mientras un club vivo rechazaba la
    /// pasada nueva con un `23514`. Lo que hay que afirmar no es que el `CHECK`
    /// **esté**, sino **qué admite** — y contra el enumerado de Swift, no contra
    /// una lista tecleada aquí, que se desincronizaría igual.
    ///
    /// # Y por qué no es un test del `INSERT`
    ///
    /// Porque insertar una pasada exige una competición, una temporada y un club,
    /// y el fallo no está en la fila: está en el texto de la constraint. Se lee
    /// del catálogo y se comprueba que **cada** caso del enumerado aparece.
    ///
    /// > **Al añadir el cuarto caso a `IngestionKind`** —el acta de `D-57`—, este
    /// > test se pone rojo hasta que exista su migración. Que es el trabajo.
    @Test("el CHECK de `kind` admite TODOS los casos del enumerado, no los de su día (D-02, D-90)")
    func theKindCheckAdmitsEveryCase() async throws {
        try await Self.withApp { app in
            let schema = "\(Self.prefix)kindcheck"
            let sql = app.db(.control) as! any SQLDatabase
            try await sql.raw("DROP SCHEMA IF EXISTS \(ident: schema) CASCADE").run()
            try await sql.raw("CREATE SCHEMA \(ident: schema)").run()

            // **Hay que fabricar un club vivo, y eso cuesta dos cosas: migrar en
            // dos lotes y falsificar el `CHECK` viejo. Las dos.**
            //
            // La primera versión de este test solo aprovisionaba un *schema*
            // limpio, y **la comprobación de mutación la tumbó**. La segunda ya
            // migraba en dos lotes, y la mutación **volvió a sobrevivir** — por un
            // motivo más de fondo: el primer lote también ejecuta el código de
            // **hoy**, así que `AddStandingsToIngestionRun` deriva su `CHECK` con
            // el enumerado de hoy y sale con los tres casos aunque nadie lo rehaga.
            //
            // **Un *schema* migrado antes de que el caso existiera no se puede
            // fabricar ejecutando el código de ahora**, porque el código de
            // entonces ya no está. Así que se escribe a mano el `CHECK` que aquel
            // código dejó — y no es una invención: es el texto **medido** en
            // `club_atleti` el 2026-09-16, antes de arreglarlo.
            //
            // Es la misma lección que `H-07` y que las tres pasadas fallidas del
            // guion de mutación de F7: **un test que no reproduce la condición no
            // es un test, es un verde**. Lo encontró la mutación dos veces
            // seguidas, no un rojo.
            let all = TenantMigrations.all()
            let upToStandings = try #require(
                all.firstIndex { $0.name.hasSuffix("AddStandingsToIngestionRun") },
                "AddStandingsToIngestionRun ya no está en la lista: el corte no significa nada")
            try await MigrateTenantsCommand.migrate(
                schema: schema, migrations: Array(all.prefix(upToStandings + 1)), on: app)

            // El `CHECK` tal y como lo dejó F7, literal.
            try await sql.raw("""
                ALTER TABLE \(ident: schema).\(ident: "ingestion_runs")
                DROP CONSTRAINT \(ident: "chk_ingestion_runs_kind")
                """).run()
            try await sql.raw("""
                ALTER TABLE \(ident: schema).\(ident: "ingestion_runs")
                ADD CONSTRAINT \(ident: "chk_ingestion_runs_kind")
                CHECK (kind IN ('calendar', 'standings'))
                """).run()

            // Testigo de que el montaje hizo lo que dice: en este punto el `CHECK`
            // existe **y le falta** el caso de F8. Sin esta comprobación, un fallo
            // del `ALTER` de arriba dejaría el test pasando por el motivo
            // equivocado — que es exactamente contra lo que avisa `H-07`.
            let beforeSecondBatch = try #require(
                try await Self.kindCheck(of: schema, on: app),
                "el primer lote no llegó a crear el CHECK")
            #expect(!beforeSecondBatch.contains("'scorers'"),
                    "el montaje no reprodujo el CHECK viejo: \(beforeSecondBatch)")

            // Y ahora el resto, que es lo que le pasa a un club vivo cuando se
            // despliega F8.
            try await MigrateTenantsCommand.migrate(schema: schema, on: app)
            #expect(try await Self.batches(of: schema, on: app) == 2,
                    "el schema no se migró en dos lotes: no reproduce a un club vivo")

            let check = try #require(
                try await Self.kindCheck(of: schema, on: app),
                "no existe chk_ingestion_runs_kind")

            // **Contra `allCases`, no contra una lista escrita aquí.** Una lista
            // tecleada en el test se desincroniza del enumerado por el mismo
            // motivo por el que se desincronizó el `CHECK`, y entonces el test
            // pasaría a ser parte del problema en vez de la guarda.
            for kind in IngestionKind.allCases {
                let diagnostic = "el CHECK del schema no admite `\(kind.rawValue)`: \(check)."
                    + " Un caso nuevo del enumerado NO llega solo a un schema ya migrado:"
                    + " hace falta una migración que lo rehaga (D-90)."
                #expect(check.contains("'\(kind.rawValue)'"), "\(diagnostic)")
            }

            try await sql.raw("DROP SCHEMA IF EXISTS \(ident: schema) CASCADE").run()
        }
    }

    /// La definición de `chk_ingestion_runs_kind` tal y como está **en la base**,
    /// que es el único sitio donde este defecto se puede ver.
    static func kindCheck(of schema: String, on app: Application) async throws -> String? {
        let sql = app.db(.control) as! any SQLDatabase
        return try await sql.raw("""
            SELECT pg_get_constraintdef(con.oid) AS line
            FROM pg_constraint con JOIN pg_namespace n ON n.oid = con.connamespace
            WHERE n.nspname = \(bind: schema) AND con.conname = 'chk_ingestion_runs_kind'
            """).first(decodingColumn: "line", as: String.self)
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
            //
            // **18 desde F8** (15 en F7): tres de `standing_rows` —`position`,
            // `previous_position` y el de los siete contadores—, dos en
            // `ingestion_runs` —`kind` y la pareja de `round_id`— y **tres nuevos
            // en `league_scorers`**: `goals >= 0`, `rank IS NULL OR rank >= 1` y
            // el de la clave de `D-93`, que impide que `federation_player_id` sea
            // la cadena vacía. El número sube con cada fase y **eso es lo que se
            // quiere**: actualizarlo obliga a mirar qué se añadió.
            //
            // **Y en F8 ese repaso cobró de verdad, que es para lo que existe.**
            // El recuento no cambia al añadir el caso `scorers` a
            // `IngestionKind` —`chk_ingestion_runs_kind` sigue siendo uno—, así
            // que si `AddScorersToIngestionRun` no rehiciera su expresión, este
            // test seguiría en verde y el club vivo rechazaría la pasada nueva.
            // Lo que lo caza es `theKindCheckAdmitsEveryCase`, más abajo: el
            // inventario cuenta constraints, no lo que dicen.
            //
            // Lo que NO hay, y es deliberado en las dos tablas, es un `CHECK` de
            // aritmética: la tabla oficial de un grupo sancionado no cumple
            // `points = 3·G + E` (`D-92`), y los goles del ranking son de
            // jugadores ajenos, sin nada nuestro contra lo que cuadrarlos (§3.7).
            #expect(before.filter { $0.hasPrefix("c chk_") }.count == 18,
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
