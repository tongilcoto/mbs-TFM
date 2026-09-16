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

/// Nivel 3 (§8.1): **la tabla de goleadores**, contra Postgres real.
///
/// **Un test por adaptador, no por regla** (Plan §5). Lo que aquí se prueba es lo
/// que el nivel 2 **no puede**, y en F8 eso son tres cosas concretas — las tres
/// señaladas por mutaciones que sobrevivían a la batería entera:
///
/// 1. **El `UNIQUE` de `D-93`.** El doble en memoria hace *upsert* por `id`, así
///    que con él la clave de negocio no existe: dos filas con el mismo
///    `federation_player_id` conviven tan tranquilas. El índice solo está en el
///    esquema, y quitarlo de la migración no rompía **ni un test**.
/// 2. **Las dos mitades del `WHERE` de la retirada** (`D-94`). El nivel 2 afirma
///    la regla contra el doble; lo que ninguna prueba alcanzaba era el `filter`
///    del adaptador de verdad — y ahí un `competition_id` que faltara vacía el
///    club entero sin dar un solo error.
/// 3. **Los tres `CHECK`**, que no viven en el tipo sino en el esquema.
///
/// > **La lección de método, que ya va por la tercera fase**: una mutación
/// > superviviente son *"falta un test"* o *"sobra el código"*. Aquí eran cuatro
/// > de lo primero, y todas apuntaban al mismo sitio — **F8 se había saltado su
/// > suite de nivel 3**, que F7 sí tiene. La comprobación de mutación no encontró
/// > un defecto: encontró un agujero en la pirámide.
@Suite("LeagueScorer · §4.4 · la clave de D-93, la retirada de D-94 y los CHECK",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct LeagueScorerPersistenceTests {

    static let prefix = "test_scorer_"
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// **Dos competiciones**, y no es decoración: sin la segunda, *"la retirada no
    /// toca lo que no es suyo"* no se puede afirmar, y ése es exactamente el
    /// `filter` que una mutación se llevaba por delante sin romper nada.
    struct Seeded: Sendable {
        let competition: CompetitionID
        let other: CompetitionID
    }

    static func withSeeded(
        _ slug: String, _ body: @escaping @Sendable (Seeded, TenantFixture) async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(
                slug, federation: .rffm, schemaPrefix: prefix, on: app)
            let tenant = TenantFixture(app: app, slug: slug, schema: "\(prefix)\(slug)")

            let season = try Season(
                id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"),
                federationSeasonID: "21", createdAt: now, updatedAt: now)
            let competition = try Competition(
                id: CompetitionID(raw: UUID()), seasonID: season.id,
                modality: .futbol11, gender: .masculino,
                federationCompetitionID: "24037548", federationGroupID: "24037549",
                ageCategory: .cadete, divisionLabel: "Primera División Autonómica",
                groupLabel: "Grupo 1", createdAt: now, updatedAt: now)
            let other = try Competition(
                id: CompetitionID(raw: UUID()), seasonID: season.id,
                modality: .futbol11, gender: .masculino,
                federationCompetitionID: "24037637", federationGroupID: "24037649",
                ageCategory: .infantil, divisionLabel: "Primera Infantil",
                groupLabel: "Grupo 12", createdAt: now, updatedAt: now)

            try await tenant.scope {
                try await $0.seasons.save(season)
                try await $0.competitions.save(competition)
                try await $0.competitions.save(other)
            }

            try await body(Seeded(competition: competition.id, other: other.id), tenant)
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    static func scorer(
        _ competition: CompetitionID,
        federationPlayerID: String = "11322891",
        fullName: String = "GEA IRISARRI, LUIS",
        teamLabel: String = "ARAVACA C.F. - CEIBA A",
        goals: Int = 31,
        rank: Int? = nil,
        syncedAt: Date? = now
    ) throws -> LeagueScorer {
        try LeagueScorer(
            id: LeagueScorerID(raw: UUID()),
            competitionID: competition,
            federationPlayerID: federationPlayerID,
            fullName: fullName,
            teamLabel: teamLabel,
            goals: goals,
            rank: rank,
            syncedAt: syncedAt,
            createdAt: now,
            updatedAt: now)
    }

    // ── El mapeo ─────────────────────────────────────────────────────────────

    @Test("la fila va y vuelve con sus siete columnas intactas (§4.4)")
    func theRowSurvivesTheRoundTrip() async throws {
        try await Self.withSeeded("sc-map") { seeded, tenant in
            let written = try Self.scorer(seeded.competition, rank: 3)
            try await tenant.scope { try await $0.leagueScorers.save(written) }

            let read = try await tenant.scope {
                try await $0.leagueScorers.list(competitionID: seeded.competition)
            }

            let row = try #require(read.first)
            #expect(row.id == written.id)
            #expect(row.competitionID == seeded.competition)
            #expect(row.federationPlayerID == "11322891")
            #expect(row.fullName == "GEA IRISARRI, LUIS")
            #expect(row.teamLabel == "ARAVACA C.F. - CEIBA A")
            #expect(row.goals == 31)
            #expect(row.rank == 3)
            #expect(row.syncedAt == Self.now)
        }
    }

    @Test("un puesto nulo va y vuelve nulo, no como cero (Anexo RFFM §F.19)")
    func aNullRankStaysNull() async throws {
        // Es el caso **normal** y no el raro: ninguna de las dos federaciones
        // publica puesto, así que un mapeo que lo colapsara a `0` pondría a
        // doscientos goleadores en la posición cero, que ni siquiera existe — el
        // `CHECK` la rechazaría y la pasada moriría con un `23514`.
        try await Self.withSeeded("sc-ranknull") { seeded, tenant in
            try await tenant.scope {
                try await $0.leagueScorers.save(try Self.scorer(seeded.competition, rank: nil))
            }
            let read = try await tenant.scope {
                try await $0.leagueScorers.list(competitionID: seeded.competition)
            }
            #expect(try #require(read.first).rank == nil)
        }
    }

    // ── La clave de D-93 ─────────────────────────────────────────────────────

    @Test("el mismo jugador no puede estar dos veces en la misma competición (D-93, §3.5)")
    func theSamePlayerCannotBeStoredTwice() async throws {
        // **La mutación que destapó este hueco**: quitar el `.unique(on:)` de la
        // migración no rompía ni un test, porque el doble del nivel 2 hace
        // *upsert* por `id` y ahí la clave de negocio sencillamente no existe.
        // Sin el índice, un fallo en el *upsert* —o un `id` mal reutilizado—
        // duplicaría al goleador en el ranking sin que nada chistara.
        try await Self.withSeeded("sc-uniq") { seeded, tenant in
            try await tenant.scope {
                try await $0.leagueScorers.save(
                    try Self.scorer(seeded.competition, federationPlayerID: "77"))
            }

            // **Ámbito nuevo a propósito** (§6.2): una violación de restricción
            // aborta la transacción entera con `25P02`, así que dos intentos que
            // deban fallar en el mismo ámbito hacen que el segundo pase por el
            // motivo equivocado.
            await #expect(throws: (any Error).self) {
                try await tenant.scope {
                    try await $0.leagueScorers.save(
                        try Self.scorer(
                            seeded.competition, federationPlayerID: "77",
                            fullName: "OTRO NOMBRE, PEPE"))
                }
            }
        }
    }

    @Test("pero SÍ puede estar en dos competiciones distintas (D-93)")
    func theSamePlayerMayAppearInTwoCompetitions() async throws {
        // La otra mitad de la clave, y no es teórica: un juvenil que juega también
        // con el primer equipo aparece en los dos rankings con el **mismo**
        // `codigo_jugador`. Un `UNIQUE` solo sobre esa columna —que es la otra
        // mutación que sobrevivía— lo haría imposible.
        try await Self.withSeeded("sc-twocomps") { seeded, tenant in
            try await tenant.scope {
                try await $0.leagueScorers.save(
                    try Self.scorer(seeded.competition, federationPlayerID: "77"))
                try await $0.leagueScorers.save(
                    try Self.scorer(seeded.other, federationPlayerID: "77"))
            }

            let here = try await tenant.scope {
                try await $0.leagueScorers.list(competitionID: seeded.competition)
            }
            let there = try await tenant.scope {
                try await $0.leagueScorers.list(competitionID: seeded.other)
            }
            #expect(here.count == 1)
            #expect(there.count == 1)
        }
    }

    // ── La retirada de D-94 ──────────────────────────────────────────────────

    @Test("la retirada se lleva lo que no trae la marca de esta pasada (D-94)")
    func retireRemovesWhatThisPassDidNotTouch() async throws {
        try await Self.withSeeded("sc-retire") { seeded, tenant in
            let mark = Self.now.addingTimeInterval(7 * 86_400)
            try await tenant.scope {
                try await $0.leagueScorers.save(
                    try Self.scorer(seeded.competition, federationPlayerID: "sigue",
                                    syncedAt: mark))
                try await $0.leagueScorers.save(
                    try Self.scorer(seeded.competition, federationPlayerID: "viejo",
                                    syncedAt: Self.now))
            }

            let retired = try await tenant.scope {
                try await $0.leagueScorers.retire(
                    competitionID: seeded.competition, keepingMark: mark)
            }

            #expect(retired == 1)
            let left = try await tenant.scope {
                try await $0.leagueScorers.list(competitionID: seeded.competition)
            }
            #expect(left.map(\.federationPlayerID) == ["sigue"])
        }
    }

    @Test("y NO toca las filas de otra competición (D-94)")
    func retireDoesNotCrossCompetitions() async throws {
        // **La mutación que destapó este hueco**: quitar
        // `.filter(\.$competition.$id == …)` del adaptador no rompía nada, porque
        // el E2E de F8 tiene una sola competición en su *schema* y el nivel 2
        // afirma la regla contra el **doble**, no contra el `WHERE` de verdad.
        //
        // Es la clase de fallo que no da error: se lleva los datos y solo se nota
        // días después, al abrir la pantalla equivocada.
        try await Self.withSeeded("sc-retirescope") { seeded, tenant in
            let mark = Self.now.addingTimeInterval(7 * 86_400)
            try await tenant.scope {
                try await $0.leagueScorers.save(
                    try Self.scorer(seeded.competition, federationPlayerID: "propio",
                                    syncedAt: mark))
                // Rancio **y de la otra competición**: cumple la condición de la
                // marca, así que lo único que lo salva es el filtro de ámbito.
                try await $0.leagueScorers.save(
                    try Self.scorer(seeded.other, federationPlayerID: "ajeno",
                                    syncedAt: Self.now))
            }

            let retired = try await tenant.scope {
                try await $0.leagueScorers.retire(
                    competitionID: seeded.competition, keepingMark: mark)
            }

            #expect(retired == 0, "se retiró algo que no era de esta competición")
            let other = try await tenant.scope {
                try await $0.leagueScorers.list(competitionID: seeded.other)
            }
            #expect(other.count == 1)
        }
    }

    @Test("y alcanza también las filas SIN marca (D-94)")
    func retireReachesUnmarkedRows() async throws {
        // **La tercera mutación superviviente.** En SQL, `synced_at != :mark`
        // evalúa a `NULL` —no a `true`— cuando la columna es nula, así que sin la
        // rama `IS NULL` esas filas serían **inmortales**: ninguna pasada las
        // retiraría jamás. Y una fila sin marca es precisamente una que ninguna
        // pasada ha confirmado.
        try await Self.withSeeded("sc-retirenull") { seeded, tenant in
            try await tenant.scope {
                try await $0.leagueScorers.save(
                    try Self.scorer(seeded.competition, federationPlayerID: "sinmarca",
                                    syncedAt: nil))
            }

            let retired = try await tenant.scope {
                try await $0.leagueScorers.retire(
                    competitionID: seeded.competition,
                    keepingMark: Self.now.addingTimeInterval(7 * 86_400))
            }

            #expect(retired == 1)
            #expect(try await tenant.scope {
                try await $0.leagueScorers.list(competitionID: seeded.competition)
            }.isEmpty)
        }
    }

    // ── El orden, que ES el dato (D-49, §5.1) ────────────────────────────────

    @Test("el ranking viene ordenado por goles descendente (D-49, §5.1)")
    func theRankingComesOrderedByGoals() async throws {
        try await Self.withSeeded("sc-order") { seeded, tenant in
            // Se escriben del revés a propósito: si el orden lo pusiera el de
            // inserción, este test pasaría sin que el `sort` existiera.
            try await tenant.scope {
                try await $0.leagueScorers.save(
                    try Self.scorer(seeded.competition, federationPlayerID: "poco", goals: 3))
                try await $0.leagueScorers.save(
                    try Self.scorer(seeded.competition, federationPlayerID: "mucho", goals: 31))
            }

            let read = try await tenant.scope {
                try await $0.leagueScorers.list(competitionID: seeded.competition)
            }
            #expect(read.map(\.goals) == [31, 3])
        }
    }

    @Test("y el empate lo rompe el nombre, para que el orden sea TOTAL (D-92 aplicada)")
    func tiesAreBrokenByName() async throws {
        // Es la lección de `D-92` traída a otra tabla: un orden que no sea total
        // deja que dos filas empatadas bailen entre dos consultas idénticas, y el
        // ranking es lo que la pantalla pinta. Allí lo destapó una mutación sobre
        // un `Dictionary`; aquí el que decide es Postgres, que tampoco promete
        // nada sin un criterio de desempate.
        try await Self.withSeeded("sc-tie") { seeded, tenant in
            try await tenant.scope {
                try await $0.leagueScorers.save(
                    try Self.scorer(seeded.competition, federationPlayerID: "z",
                                    fullName: "ZAMORA, LUIS", goals: 45))
                try await $0.leagueScorers.save(
                    try Self.scorer(seeded.competition, federationPlayerID: "a",
                                    fullName: "ABAD, LUIS", goals: 45))
            }

            let read = try await tenant.scope {
                try await $0.leagueScorers.list(competitionID: seeded.competition)
            }
            #expect(read.map(\.fullName) == ["ABAD, LUIS", "ZAMORA, LUIS"])
        }
    }

    // ── Los tres CHECK ───────────────────────────────────────────────────────

    /// Inserta **en SQL crudo**, saltándose el Dominio a propósito.
    ///
    /// Es la única forma de probar un `CHECK`: la entidad ya rechaza estos valores
    /// en su `init`, así que por el repositorio no se llega nunca al esquema. Y
    /// llegar hace falta, porque `D-28` decidió bajar estas guardas a la base — un
    /// *script*, una migración de datos o un `psql` no pasan por Swift.
    static func insertRaw(
        _ tenant: TenantFixture, competition: CompetitionID,
        federationPlayerID: String, goals: Int
    ) async throws {
        try await tenant.raw.raw("""
            INSERT INTO \(ident: tenant.schema).\(ident: "league_scorers")
              (id, competition_id, federation_player_id, full_name, team_label, goals,
               created_at, updated_at)
            VALUES (\(bind: UUID()), \(bind: competition.raw),
                    \(bind: federationPlayerID), 'A', 'B', \(bind: goals), now(), now())
            """).run()
    }

    @Test("el esquema rechaza unos goles negativos (§4.6, spec `minimum: 0`)")
    func theSchemaRejectsNegativeGoals() async throws {
        try await Self.withSeeded("sc-chkgoals") { seeded, tenant in
            await #expect(throws: (any Error).self) {
                try await Self.insertRaw(
                    tenant, competition: seeded.competition,
                    federationPlayerID: "77", goals: -1)
            }
        }
    }

    @Test("y una clave de federación en blanco (D-93)")
    func theSchemaRejectsABlankFederationPlayerID() async throws {
        // **Un `NOT NULL` no lo impide**, y la cadena vacía sería peor que la
        // ausencia: el `UNIQUE` la dejaría existir **una** vez por competición, y
        // cada pasada le escribiría encima los datos de un goleador distinto.
        try await Self.withSeeded("sc-chkkey") { seeded, tenant in
            await #expect(throws: (any Error).self) {
                try await Self.insertRaw(
                    tenant, competition: seeded.competition,
                    federationPlayerID: "   ", goals: 3)
            }
        }
    }

    @Test("pero SÍ acepta cero goles, que es una fila válida (§3.2)")
    func theSchemaAcceptsZeroGoals() async throws {
        // La mitad que evita que el `CHECK` se escriba de más: un `goals > 0`
        // parece igual de razonable y dejaría fuera al que la FCF publica en el
        // puesto 50 sin haber marcado.
        try await Self.withSeeded("sc-chkzero") { seeded, tenant in
            try await Self.insertRaw(
                tenant, competition: seeded.competition,
                federationPlayerID: "77", goals: 0)
            let read = try await tenant.scope {
                try await $0.leagueScorers.list(competitionID: seeded.competition)
            }
            #expect(read.count == 1)
        }
    }

    @Test("pero NO hay ningún CHECK de aritmética, y eso es deliberado (§3.7)")
    func thereIsNoArithmeticCheck() async throws {
        // La mutación inversa, igual que en `standing_rows` y por un motivo aún
        // más directo: estos goles son de jugadores **ajenos** y no hay nada
        // nuestro contra lo que cuadrarlos —`Goal` solo cubre los partidos del
        // club—. Un `CHECK` de más aquí no sería una comprobación cara: sería una
        // comprobación imposible que mataría la pasada con un `23514`.
        try await Self.withSeeded("sc-noarith") { seeded, tenant in
            try await tenant.scope {
                try await $0.leagueScorers.save(
                    try Self.scorer(seeded.competition, goals: 500))
            }
            let read = try await tenant.scope {
                try await $0.leagueScorers.list(competitionID: seeded.competition)
            }
            #expect(try #require(read.first).goals == 500)
        }
    }
}
