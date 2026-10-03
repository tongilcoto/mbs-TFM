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
                try await Self.check("chk_ingestion_runs_kind", of: schema, on: app),
                "el primer lote no llegó a crear el CHECK")
            #expect(!beforeSecondBatch.contains("'scorers'"),
                    "el montaje no reprodujo el CHECK viejo: \(beforeSecondBatch)")

            // Y ahora el resto, que es lo que le pasa a un club vivo cuando se
            // despliega F8.
            try await MigrateTenantsCommand.migrate(schema: schema, on: app)
            #expect(try await Self.batches(of: schema, on: app) == 2,
                    "el schema no se migró en dos lotes: no reproduce a un club vivo")

            let check = try #require(
                try await Self.check("chk_ingestion_runs_kind", of: schema, on: app),
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

    /// La definición de un `CHECK` tal y como está **en la base**, que es el
    /// único sitio donde este defecto se puede ver.
    ///
    /// **Se generalizó en F10-bis**, cuando hizo falta la segunda: `kind` y
    /// `outcome` son el mismo defecto en dos columnas, y dos consultas idénticas
    /// con el nombre cambiado se desincronizarían la una de la otra.
    static func check(
        _ name: String, of schema: String, on app: Application
    ) async throws -> String? {
        let sql = app.db(.control) as! any SQLDatabase
        return try await sql.raw("""
            SELECT pg_get_constraintdef(con.oid) AS line
            FROM pg_constraint con JOIN pg_namespace n ON n.oid = con.connamespace
            WHERE n.nspname = \(bind: schema) AND con.conname = \(bind: name)
            """).first(decodingColumn: "line", as: String.self)
    }

    // ── F10-bis · el mismo defecto, la columna de al lado ───────────────────

    /// **La lección de F8 cobrándose por segunda vez, y otra vez la destapó la
    /// mutación.**
    ///
    /// `C-A.4` añade `accepted` a `IngestionOutcome` y `AllowAcceptedIngestionRun`
    /// rehace su `CHECK`. Quitar ese `replaceCheckConstraint` **sobrevivía a toda
    /// la batería**: en los tests cada tenant nace limpio, así que
    /// `CreateIngestionRun` deriva el `CHECK` con el enumerado de **hoy** y los
    /// tres valores entran igual. El que se rompe es el **club vivo**, que es el
    /// único que no se puede fabricar ejecutando el código de ahora.
    ///
    /// Así que se fabrica como F8 enseñó: migrar hasta el lote anterior y
    /// escribir a mano el `CHECK` que aquel código dejó —`succeeded`/`failed`,
    /// que es lo que `IngestionOutcome` tenía antes de `C-A.4`—. Sin ese montaje
    /// el test pasa por el motivo equivocado, que es lo que `H-07` avisa.
    ///
    /// > **Al añadir el cuarto caso a `IngestionOutcome`**, este test se pone
    /// > rojo hasta que exista su migración. Que es el trabajo.
    @Test("el CHECK de `outcome` admite TODOS los casos, también en un club vivo (D-02, D-90)")
    func theOutcomeCheckAdmitsEveryCase() async throws {
        try await Self.withApp { app in
            let schema = "\(Self.prefix)outcomecheck"
            let sql = app.db(.control) as! any SQLDatabase
            try await sql.raw("DROP SCHEMA IF EXISTS \(ident: schema) CASCADE").run()
            try await sql.raw("CREATE SCHEMA \(ident: schema)").run()

            let all = TenantMigrations.all()
            let upToScorers = try #require(
                all.firstIndex { $0.name.hasSuffix("AddScorersToIngestionRun") },
                "AddScorersToIngestionRun ya no está en la lista: el corte no significa nada")
            try await MigrateTenantsCommand.migrate(
                schema: schema, migrations: Array(all.prefix(upToScorers + 1)), on: app)

            // El `CHECK` tal y como lo dejó `CreateIngestionRun` cuando
            // `IngestionOutcome` tenía dos casos, que es hasta `C-A.4`.
            try await sql.raw("""
                ALTER TABLE \(ident: schema).\(ident: "ingestion_runs")
                DROP CONSTRAINT \(ident: "chk_ingestion_runs_outcome")
                """).run()
            try await sql.raw("""
                ALTER TABLE \(ident: schema).\(ident: "ingestion_runs")
                ADD CONSTRAINT \(ident: "chk_ingestion_runs_outcome")
                CHECK (outcome IN ('succeeded', 'failed'))
                """).run()

            // Testigo del montaje, por lo mismo que en el test de `kind`.
            let beforeSecondBatch = try #require(
                try await Self.check("chk_ingestion_runs_outcome", of: schema, on: app),
                "el primer lote no llegó a crear el CHECK")
            #expect(!beforeSecondBatch.contains("'accepted'"),
                    "el montaje no reprodujo el CHECK viejo: \(beforeSecondBatch)")

            // Y ahora el resto, que es lo que le pasa a un club vivo al desplegar.
            try await MigrateTenantsCommand.migrate(schema: schema, on: app)
            #expect(try await Self.batches(of: schema, on: app) == 2,
                    "el schema no se migró en dos lotes: no reproduce a un club vivo")

            let check = try #require(
                try await Self.check("chk_ingestion_runs_outcome", of: schema, on: app),
                "no existe chk_ingestion_runs_outcome")

            for outcome in IngestionOutcome.allCases {
                let diagnostic = "el CHECK del schema no admite `\(outcome.rawValue)`: \(check)."
                    + " Un caso nuevo del enumerado NO llega solo a un schema ya migrado:"
                    + " hace falta una migración que lo rehaga (D-90)."
                #expect(check.contains("'\(outcome.rawValue)'"), "\(diagnostic)")
            }

            try await sql.raw("DROP SCHEMA IF EXISTS \(ident: schema) CASCADE").run()
        }
    }

    /// **`C-D.7` · el ancla del recuento, y es ancla y no regla.**
    ///
    /// No hay aquí un comportamiento que pueda romperse: lo que hay es un número
    /// que **obliga a mirar** qué se añadió, exactamente como el recuento de
    /// `CHECK` de más abajo. Una fase que añada una migración pone este test en
    /// rojo y tiene que explicarse en el renglón; una que añada **dos sin
    /// querer** —editando una aplicada y creando su sustituta— también.
    ///
    /// **13 en F8, 14 con F10-bis, 16 con el Bloque D de F10**: la tabla de
    /// [D-68] con la FK compuesta y los dos índices de `Match` (`C-D.3`/`C-D.4`),
    /// y aparte la retirada del índice por `finished_at` (`C-D.6`). **Son dos y
    /// no una** porque no son la misma razón, y una migración que hace dos cosas
    /// no se revierte a medias.
    ///
    /// **La segunda mitad es la que de verdad puede morder**: Fluent indexa por
    /// **nombre** ([D-90]), así que dos migraciones homónimas serían una sola
    /// aplicada y la otra saltada **en silencio** — sin error y sin nada que lo
    /// diga, que es la misma forma de fallar de H-31.
    @Test("las migraciones por tenant son 16, y ningún nombre se repite (C-D.7, D-90)")
    func theTenantMigrationListIsAnchored() throws {
        let nombres = TenantMigrations.all().map(\.name)
        #expect(nombres.count == 16,
                "cambió el número de migraciones: \(nombres.joined(separator: " · "))")
        #expect(Set(nombres).count == nombres.count,
                "hay nombres repetidos: Fluent aplicaría una y saltaría la otra en silencio")
    }

    /// **`A-5`·H-36: §4.6 manda dos índices compuestos en `Match` y no existía
    /// ninguno.** La sección es explícita —*"índice compuesto en
    /// `Match`(`competition_id`, `home_team_id`) y (`competition_id`,
    /// `away_team_id`): son los que sostienen la composición de la competición
    /// ahora que no hay tabla pivote (§3.4, [D-27])"*— y `CreateMatch` creaba
    /// **cuatro de una sola columna**.
    ///
    /// La auditoría lo anotó como **discrepancia código↔diseño** y no como
    /// rendimiento (que está fuera de alcance), y la regla obliga a decir cuál de
    /// los dos lados está mal: el diseño tiene el argumento escrito y [D-27]
    /// sigue en pie, así que **falta el índice**. Cae en F10 porque es cambio de
    /// esquema y por [D-90] va en una migración **nueva** — la de
    /// `TeamRegistration`, que es la que esta fase ya escribe.
    ///
    /// **Se afirma sobre el catálogo y por columnas, no por nombre**: lo que §4.6
    /// pide es la pareja de columnas en ese orden, y un índice con el nombre
    /// correcto sobre las columnas equivocadas cumpliría un test por nombre sin
    /// sostener nada.
    @Test("los dos índices compuestos de Match existen y son compuestos (A-5·H-36, §4.6)")
    func matchHasItsCompositeIndexes() async throws {
        try await Self.withApp { app in
            try await Self.cleanUp(["idx"], on: app)
            let schema = try await Self.provision("idx", on: app)

            let inventory = try await Self.inventory(of: schema, on: app)
            for lado in ["home_team_id", "away_team_id"] {
                #expect(
                    inventory.contains {
                        $0.contains("ON TENANT.matches")
                            && $0.contains("(competition_id, \(lado))")
                    },
                    "falta el índice compuesto (competition_id, \(lado)) de §4.6"
                )
            }

            try await Self.cleanUp(["idx"], on: app)
        }
    }

    /// **`C-D.6` · el índice viejo se retira, y lo pidió la mutación.**
    ///
    /// `CreateIngestionRun` dejó `idx_ingestion_runs_competition` sobre
    /// (`competition_id`, `finished_at`) porque ése era el orden del registro.
    /// F10-bis añadió su pareja por `started_at` y dejó el viejo en pie **a
    /// propósito**, porque hasta `C-D.6` seguía siendo el que la consulta usaba.
    /// Ya no lo usa nadie.
    ///
    /// **Sin este test, vaciar `DropFinishedAtIngestionRunIndex` pasaba toda la
    /// batería** (`M14` sobrevivía): el inventario del `revert` compara los dos
    /// lados entre sí, así que no nota lo que **sobra** en los dos. Es la misma
    /// forma de fallar que las dos anclas absolutas de más abajo vienen a tapar.
    @Test("el índice por finished_at ya no está, y sí el de started_at (C-D.6, D-96)")
    func theFinishedAtRunIndexIsRetired() async throws {
        try await Self.withApp { app in
            try await Self.cleanUp(["dropidx"], on: app)
            let schema = try await Self.provision("dropidx", on: app)

            let inventory = try await Self.inventory(of: schema, on: app)
            // **Por igualdad exacta sobre el renglón de `pg_class`, y lo pidió la
            // mutación.** La primera versión preguntaba por un `contains` de
            // `idx_ingestion_runs_competition"` —con una comilla que `pg_indexes`
            // no escribe—, así que no casaba con nada y **pasaba siempre**:
            // `M14` sobrevivía a un test que no afirmaba nada. Es la misma
            // lección que `M3` del Bloque B, en otro sitio: el verde de una
            // aserción vacía es indistinguible del verde de una que funciona.
            #expect(!inventory.contains("i idx_ingestion_runs_competition"),
                    "sigue el índice por finished_at, que ya no tiene un solo lector")
            // **Y la otra mitad**: retirar el viejo no puede llevarse al que la
            // consulta usa ahora. Sin esto, tirar los dos también pasaría.
            #expect(inventory.contains {
                        $0.contains("ON TENANT.ingestion_runs")
                            && $0.contains("(competition_id, started_at)")
                    },
                    "falta el índice por started_at, que es el que sostiene el orden de C-D.6")

            try await Self.cleanUp(["dropidx"], on: app)
        }
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
            //
            // **19 desde F10-bis** (18 en F8): el que sube es
            // `chk_ingestion_runs_finished`, la pareja de [D-96] —*"aceptada si y
            // solo si no hay final"*— bajada a la tabla. El `CHECK` de `outcome`
            // **no** suma: se rehizo, no se añadió, que es justo la distinción que
            // el párrafo de arriba aprendió en F8 y la razón de que este recuento
            // por sí solo no baste.
            #expect(before.filter { $0.hasPrefix("c chk_") }.count == 19,
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
    /// viejo. El camino B reproduce **los tres primeros lotes de `club_atleti`**
    /// —`Club` (F0), `Season` y `Competition` (F1), y el resto—, y lo que importa
    /// de ellos no es que sean tres sino **el orden**: `OpponentClub` y `Team` van
    /// en la lista *antes* de `Competition` y el club vivo las aplicó *después*.
    ///
    /// **`A-13`·H-81: la primera versión no lo reproducía.** Aplicaba
    /// `prefix(2)` y luego el resto, que es la lista de registro partida en dos
    /// lotes **en el mismo orden**: un `prepare` que dependiera del orden
    /// sobrevivía a toda la suite (mutación `M-A13-1`). Partir en lotes no basta;
    /// hay que sacar a `Competition` de su sitio.
    @Test("dos clubes migrados por caminos distintos convergen (H-30, §4.7)")
    func bothPathsConvergeOnTheSameSchema() async throws {
        try await Self.withApp { app in
            try await Self.cleanUp(["path-a", "path-b"], on: app)

            // Camino A: alta limpia, juego completo de una vez.
            let a = try await Self.provision("path-a", on: app)

            // Camino B: los lotes de `club_atleti`, por nombre y sacados de la
            // lista, no tecleados: si alguna desaparece, el corte no significa
            // nada y el `#require` lo dice.
            let all = TenantMigrations.all()
            func named(_ suffixes: String...) throws -> [any Migration] {
                try suffixes.map { suffix in
                    try #require(all.first { $0.name.hasSuffix(".\(suffix)") },
                                 "\(suffix) ya no está en la lista")
                }
            }
            let b = "\(Self.prefix)path-b"
            let sql = app.db(.control) as! any SQLDatabase
            try await sql.raw("CREATE SCHEMA IF NOT EXISTS \(ident: b)").run()
            try await MigrateTenantsCommand.migrate(
                schema: b, migrations: try named("CreateClub"), on: app)
            try await MigrateTenantsCommand.migrate(
                schema: b, migrations: try named("CreateClub", "CreateSeason", "CreateCompetition"),
                on: app)
            try await MigrateTenantsCommand.migrate(schema: b, on: app)

            #expect(try await Self.batches(of: b, on: app) == 3,
                    "el camino B no fue incremental: el test compara dos altas limpias")
            #expect(try await Self.batches(of: a, on: app) == 1)

            // **Testigo de la inversión**, que es lo que el test viene a medir:
            // `Competition` aplicada en un lote anterior a `Team`. Sin esto, un
            // cambio en la lista que devolviera el orden de registro dejaría el
            // test pasando por el motivo equivocado (`H-07`).
            let batchOf = { (name: String) async throws -> Int? in
                try await sql.raw("""
                    SELECT batch FROM \(ident: b).\(ident: "_fluent_migrations")
                    WHERE name = \(bind: "Persistence.\(name)")
                    """).first(decodingColumn: "batch", as: Int.self)
            }
            let competition = try #require(try await batchOf("CreateCompetition"))
            let team = try #require(try await batchOf("CreateTeam"))
            #expect(competition < team,
                    "el camino B aplicó Team antes que Competition: es el orden de un alta limpia")

            let inventoryA = try await Self.inventory(of: a, on: app)
            let inventoryB = try await Self.inventory(of: b, on: app)
            #expect(inventoryA == inventoryB,
                    "el esquema de un club depende de cuándo se dio de alta (§4.7)")

            try await sql.raw("DROP SCHEMA IF EXISTS \(ident: b) CASCADE").run()
            try await Self.cleanUp(["path-a", "path-b"], on: app)
        }
    }

    /// **`A-13`·H-80: `--revert --yes` tiene que revertir, y eso solo se ve
    /// cruzando el parser.**
    ///
    /// ConsoleKit consume `--yes`/`-y` como bandera **global** antes de parsear
    /// la firma del comando (`GlobalSignature`) y la deja en
    /// `console.confirmOverride`, así que el `@Flag("yes")` propio llegaba
    /// siempre a `false`: la guarda de H-32 saltaba y no tenía salida. El test
    /// de nivel 1 de abajo prueba `authorizeRevert` a pelo y por eso seguía en
    /// verde. Aquí se ejecuta **lo que teclea el operador**, por el mismo grupo
    /// de comandos que `Run/main.swift`, y se mira la base.
    @Test("--revert --yes revierte de verdad, pasando por el parser (A-13·H-80, H-32)")
    func revertWithYesRevertsThroughTheParser() async throws {
        try await Self.withApp { app in
            try await Self.cleanUp(["cli"], on: app)
            let schema = try await Self.provision("cli", on: app)

            // El reverso primero: sin `--yes`, por el mismo camino, no se toca nada.
            await #expect(throws: MigrateTenantsCommand.RevertNotConfirmed.self) {
                try await Self.runCommand(["migrate-tenants", "-t", "cli", "--revert"], on: app)
            }
            #expect(try await Self.batches(of: schema, on: app) == 1,
                    "la guarda dejó pasar un --revert sin confirmar")

            await #expect(throws: Never.self, "--yes no llegó a la guarda: la sigue parando") {
                try await Self.runCommand(["migrate-tenants", "-t", "cli", "--revert", "--yes"], on: app)
            }
            #expect(try await Self.batches(of: schema, on: app) == 0,
                    "--revert --yes no revirtió: la confirmación no llega al comando")

            try await Self.cleanUp(["cli"], on: app)
        }
    }

    /// Un comando **tal como lo ejecuta `Run`**: el grupo de la aplicación y una
    /// línea de argumentos, de modo que pasen por `GlobalSignature` igual que en
    /// producción.
    static func runCommand(_ arguments: [String], on app: Application) async throws {
        var context = CommandContext(
            console: app.console, input: CommandInput(arguments: ["Run"] + arguments))
        context.application = app
        try await app.console.run(app.asyncCommands.group(), with: context)
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

/// Nivel 1, **sin base**: el enumerado de hoy contra lo que **los clubes vivos
/// tienen congelado** en sus `CHECK` (`A-13`·H-82).
///
/// `D-02` deriva cada `CHECK` de su enumerado y `D-90` explica por qué eso no
/// basta: la derivación ocurre **cuando la migración corre**, y su texto se
/// queda en el *schema*. Un caso nuevo —o un `rawValue` renombrado— no llega a
/// un club ya migrado sin una migración que lo rehaga, y la batería no lo ve,
/// porque en los tests cada tenant nace limpio. F8 y F10-bis lo aprendieron con
/// `kind` y `outcome`, y sus dos tests de arriba los guardan; **los otros ocho
/// `CHECK` no tenían nada**.
@Suite("Los CHECK de enumerado: lo que el club vivo tiene congelado (A-13·H-82, D-02, D-90)")
struct FrozenEnumCheckTests {

    /// Un enumerado con `CHECK`, y **los valores que su última migración
    /// congeló** en los clubes vivos.
    ///
    /// **Aquí la lista tecleada es el punto, no el defecto.** Los tests de
    /// `kind` y `outcome` comparan contra `allCases` porque lo que afirman es
    /// *"el schema admite todo el enumerado"*; éste afirma lo contrario —*"el
    /// enumerado no se ha movido de lo que el schema tiene"*—, y lo que el
    /// *schema* tiene **es** una lista fija: la que salió el día que corrió la
    /// migración. Medida contra `club_atleti` el 2026-10-03 con
    /// `pg_get_constraintdef`: 10/10 iguales.
    struct Frozen: Sendable, CustomTestStringConvertible {
        let enumName: String
        let current: [String]
        let frozen: [String]
        let checks: [String]
        let lastDerivedBy: String
        var testDescription: String { enumName }
    }

    static let anchors: [Frozen] = [
        Frozen(enumName: "FederationCode",
               current: FederationCode.allCases.map(\.rawValue),
               frozen: ["rffm", "fcf"],
               checks: ["chk_clubs_federation"], lastDerivedBy: "CreateClub"),
        Frozen(enumName: "MatchStatus",
               current: MatchStatus.allCases.map(\.rawValue),
               frozen: ["programado", "finalizado", "aplazado", "suspendido"],
               checks: ["chk_matches_status"], lastDerivedBy: "CreateMatch"),
        Frozen(enumName: "TeamCategory",
               current: TeamCategory.allCases.map(\.rawValue),
               frozen: ["prebenjamin", "benjamin", "alevin", "infantil", "cadete", "juvenil", "senior"],
               checks: ["chk_teams_category", "chk_competitions_age_category"],
               lastDerivedBy: "CreateTeam y CreateCompetition"),
        Frozen(enumName: "Gender",
               current: Gender.allCases.map(\.rawValue),
               frozen: ["masculino", "femenino", "mixto"],
               checks: ["chk_teams_gender", "chk_competitions_gender"],
               lastDerivedBy: "CreateTeam y CreateCompetition"),
        Frozen(enumName: "Modality",
               current: Modality.allCases.map(\.rawValue),
               frozen: ["futbol_11", "futbol_7", "futbol_5", "futbol_sala", "futbol_playa"],
               checks: ["chk_teams_modality", "chk_competitions_modality"],
               lastDerivedBy: "CreateTeam y CreateCompetition"),
    ]

    /// **Al añadir o renombrar un caso**, este test se pone rojo hasta que
    /// exista la migración que rehaga sus `CHECK` con `replaceCheckConstraint`
    /// —y un test de club vivo como los de `kind` y `outcome`—. Entonces se
    /// actualiza `frozen` y `lastDerivedBy`. Que es el trabajo.
    @Test("el enumerado no se ha movido de lo que su CHECK tiene congelado", arguments: anchors)
    func theEnumMatchesWhatLiveClubsHaveFrozen(_ anchor: Frozen) {
        #expect(Set(anchor.current) == Set(anchor.frozen),
                """
                \(anchor.enumName) es hoy \(anchor.current.sorted()), y los clubes vivos \
                tienen \(anchor.frozen.sorted()) congelado en \(anchor.checks.joined(separator: " y ")) \
                desde \(anchor.lastDerivedBy). Un club ya migrado rechazará el valor nuevo con un \
                23514: hace falta una migración nueva que rehaga esos CHECK (D-90), y luego \
                actualizar este ancla.
                """)
    }
}
