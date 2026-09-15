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

/// Nivel 3 (§8.1): **la tabla de la clasificación**, contra Postgres real.
///
/// **Un test por adaptador, no por regla** (Plan §5). La aritmética y el orden ya
/// los cubrió el nivel 1 en milisegundos; lo que aquí se prueba es lo que allí no
/// se puede: el **mapeo** entidad ↔ columna, el `UNIQUE` de §3.5 y **los tres
/// `CHECK`**, que no viven en el tipo sino en el índice y en el esquema.
///
/// # Y un cuarto asunto, que es el que más caro sale descubrir tarde
///
/// Que la tabla **no** tenga `CHECK` de aritmética. El Dominio decidió no exigir
/// `points = 3·G + E` porque la tabla oficial de un grupo sancionado no lo cumple
/// (`D-92`), y esa decisión se rompe en dos sitios: en la entidad —donde hay un
/// test— y aquí, donde bastaría una línea de más en la migración para que la
/// pasada muriera con un `23514` que nadie relacionaría con una sanción
/// deportiva. Así que hay un test por cada sitio.
@Suite("StandingRow · §4.4 · el mapeo, la clave de §3.5 y los CHECK",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct StandingPersistenceTests {

    static let prefix = "test_standing_"
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// Siembra el árbol entero del que cuelga una fila: temporada, competición,
    /// jornada y dos equipos.
    struct Seeded: Sendable {
        let competition: CompetitionID
        let round: RoundID
        let otherRound: RoundID
        let teamA: TeamID
        let teamB: TeamID
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
            let round = try Round(
                id: RoundID(raw: UUID()), competitionID: competition.id, number: 30,
                startDate: now, endDate: now, createdAt: now, updatedAt: now)
            let otherRound = try Round(
                id: RoundID(raw: UUID()), competitionID: competition.id, number: 29,
                startDate: now, endDate: now, createdAt: now, updatedAt: now)
            let teamA = try Team(
                id: TeamID(raw: UUID()), opponentClubID: nil, category: .cadete,
                letter: "A", gender: .masculino, modality: .futbol11,
                createdAt: now, updatedAt: now)
            let teamB = try Team(
                id: TeamID(raw: UUID()), opponentClubID: nil, category: .cadete,
                letter: "B", gender: .masculino, modality: .futbol11,
                createdAt: now, updatedAt: now)

            try await tenant.scope {
                try await $0.seasons.save(season)
                try await $0.competitions.save(competition)
                try await $0.rounds.save(round)
                try await $0.rounds.save(otherRound)
                try await $0.teams.save(teamA)
                try await $0.teams.save(teamB)
            }

            try await body(
                Seeded(competition: competition.id, round: round.id,
                       otherRound: otherRound.id, teamA: teamA.id, teamB: teamB.id),
                tenant)
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    static func row(
        _ seeded: Seeded,
        round: RoundID? = nil,
        team: TeamID? = nil,
        position: Int = 1,
        previousPosition: Int? = nil,
        played: Int = 30, won: Int = 23, drawn: Int = 4, lost: Int = 3,
        goalsFor: Int = 78, goalsAgainst: Int = 23, points: Int = 73
    ) throws -> StandingRow {
        try StandingRow(
            id: StandingRowID(raw: UUID()),
            competitionID: seeded.competition,
            roundID: round ?? seeded.round,
            teamID: team ?? seeded.teamA,
            position: position,
            previousPosition: previousPosition,
            played: played, won: won, drawn: drawn, lost: lost,
            goalsFor: goalsFor, goalsAgainst: goalsAgainst, points: points,
            createdAt: now, updatedAt: now)
    }

    // ── El mapeo ─────────────────────────────────────────────────────────────

    @Test("la fila va y vuelve con sus trece columnas intactas (§4.4)")
    func theRowSurvivesTheRoundTrip() async throws {
        try await Self.withSeeded("st-map") { seeded, tenant in
            let written = try Self.row(seeded, position: 2, previousPosition: 5)
            try await tenant.scope { try await $0.standingRows.save(written) }

            let read = try await tenant.scope {
                try await $0.standingRows.list(roundID: seeded.round)
            }

            let row = try #require(read.first)
            #expect(row.id == written.id)
            #expect(row.competitionID == seeded.competition)
            #expect(row.roundID == seeded.round)
            #expect(row.teamID == seeded.teamA)
            #expect(row.position == 2)
            #expect(row.previousPosition == 5)
            #expect(row.played == 30)
            #expect(row.won == 23)
            #expect(row.drawn == 4)
            #expect(row.lost == 3)
            #expect(row.goalsFor == 78)
            #expect(row.goalsAgainst == 23)
            #expect(row.points == 73)
        }
    }

    @Test("`previousPosition` nula va y vuelve nula, no como cero (D-33)")
    func anullPreviousPositionStaysNull() async throws {
        // Es la diferencia entre *"no hay jornada anterior"* y *"estaba en la
        // posición 0"*, que no existe. Un mapeo que la colapsara haría que la
        // pantalla pintara una posición en vez del guion del mockup.
        try await Self.withSeeded("st-prevnull") { seeded, tenant in
            try await tenant.scope {
                try await $0.standingRows.save(try Self.row(seeded, previousPosition: nil))
            }
            let read = try await tenant.scope {
                try await $0.standingRows.list(roundID: seeded.round)
            }
            #expect(try #require(read.first).previousPosition == nil)
        }
    }

    @Test("la lista viene ordenada por posición (§5.1)")
    func thelistComesOrderedByPosition() async throws {
        try await Self.withSeeded("st-order") { seeded, tenant in
            // Se escriben del revés a propósito: si el orden lo pusiera el orden
            // de inserción, este test pasaría sin que el `sort` existiera.
            try await tenant.scope {
                try await $0.standingRows.save(
                    try Self.row(seeded, team: seeded.teamB, position: 2))
                try await $0.standingRows.save(
                    try Self.row(seeded, team: seeded.teamA, position: 1))
            }

            let read = try await tenant.scope {
                try await $0.standingRows.list(roundID: seeded.round)
            }
            #expect(read.map(\.position) == [1, 2])
            #expect(read.map(\.teamID) == [seeded.teamA, seeded.teamB])
        }
    }

    @Test("la lista es de una jornada, no de la competición (D-33)")
    func thelistIsScopedToOneRound() async throws {
        // Es lo que hace que la tabla sea un *snapshot* y lo que permite resolver
        // la columna PREV: pedir la jornada 29 tiene que traer la 29 y nada más.
        try await Self.withSeeded("st-scope") { seeded, tenant in
            try await tenant.scope {
                try await $0.standingRows.save(try Self.row(seeded, position: 1))
                try await $0.standingRows.save(
                    try Self.row(seeded, round: seeded.otherRound, position: 3))
            }

            let thirty = try await tenant.scope {
                try await $0.standingRows.list(roundID: seeded.round)
            }
            let twentyNine = try await tenant.scope {
                try await $0.standingRows.list(roundID: seeded.otherRound)
            }
            #expect(thirty.map(\.position) == [1])
            #expect(twentyNine.map(\.position) == [3])
        }
    }

    @Test("el *upsert* por id reescribe la fila, no la duplica (§4.3)")
    func savingTwiceUpdatesInPlace() async throws {
        try await Self.withSeeded("st-upsert") { seeded, tenant in
            let first = try Self.row(seeded, position: 3, points: 70)
            try await tenant.scope { try await $0.standingRows.save(first) }

            // La misma fila con el marcador de la semana siguiente. El id lo pone
            // el caso de uso, que es lo que permite reescribirla sin releerla.
            let updated = try StandingRow(
                id: first.id, competitionID: first.competitionID, roundID: first.roundID,
                teamID: first.teamID, position: 1, previousPosition: 3,
                played: 30, won: 23, drawn: 4, lost: 3,
                goalsFor: 78, goalsAgainst: 23, points: 73,
                createdAt: Self.now, updatedAt: Self.now)
            try await tenant.scope { try await $0.standingRows.save(updated) }

            let read = try await tenant.scope {
                try await $0.standingRows.list(roundID: seeded.round)
            }
            #expect(read.count == 1)
            #expect(read.first?.position == 1)
            #expect(read.first?.points == 73)
        }
    }

    // ── La clave de §3.5 ─────────────────────────────────────────────────────

    @Test("el mismo equipo dos veces en la misma jornada no cabe (§3.5)")
    func thesameTeamTwiceInARoundIsRejected() async throws {
        // El `UNIQUE(round_id, team_id)` **es** la identidad de negocio de la
        // fila: un *snapshot* es (jornada, equipo). Sin él, dos pasadas con ids
        // distintos dejarían dos clasificaciones superpuestas de la misma jornada
        // y la pantalla mostraría 32 equipos de 16.
        try await Self.withSeeded("st-unique") { seeded, tenant in
            try await tenant.scope {
                try await $0.standingRows.save(try Self.row(seeded, position: 1))
            }

            // Ámbito propio: una violación de restricción aborta la transacción
            // entera (`25P02`), así que el intento que debe fallar va solo.
            await #expect(throws: (any Error).self) {
                try await tenant.scope {
                    try await $0.standingRows.save(try Self.row(seeded, position: 2))
                }
            }
        }
    }

    @Test("el mismo equipo en otra jornada sí cabe (§3.2)")
    func thesameTeamInAnotherRoundIsFine() async throws {
        // El reverso, y hace falta: sin él, un `UNIQUE` puesto solo sobre
        // `team_id` pasaría el test de arriba y rompería la tabla entera.
        try await Self.withSeeded("st-unique-ok") { seeded, tenant in
            try await tenant.scope {
                try await $0.standingRows.save(try Self.row(seeded, position: 1))
                try await $0.standingRows.save(
                    try Self.row(seeded, round: seeded.otherRound, position: 1))
            }

            let thirty = try await tenant.scope {
                try await $0.standingRows.list(roundID: seeded.round)
            }
            #expect(thirty.count == 1)
        }
    }

    // ── Los CHECK, que no viven en el tipo ───────────────────────────────────

    @Test("el esquema rechaza una posición cero aunque el Dominio no esté delante (D-28)")
    func theschemaRejectsPositionZero() async throws {
        // El Dominio ya lo impide, pero `D-28` baja la invariante también aquí y
        // por una razón concreta: la entidad no es la única puerta a la tabla —un
        // `UPDATE` a mano, una migración futura o un repositorio nuevo la
        // esquivan—. Se comprueba con SQL crudo justamente por eso: **entrando
        // por donde el Dominio no mira**.
        try await Self.withSeeded("st-chk-pos") { seeded, tenant in
            await #expect(throws: (any Error).self) {
                try await Self.insertRaw(position: 0, points: 73, seeded: seeded, on: tenant)
            }
        }
    }

    @Test("el esquema rechaza un contador negativo (D-28)")
    func theschemaRejectsNegativeCounters() async throws {
        try await Self.withSeeded("st-chk-neg") { seeded, tenant in
            await #expect(throws: (any Error).self) {
                try await Self.insertRaw(position: 1, points: -1, seeded: seeded, on: tenant)
            }
        }
    }

    @Test("el esquema NO exige que los puntos cuadren con G/E/P (D-92)")
    func theschemaDoesNotEnforceArithmetic() async throws {
        // **La mitad que hay que resistirse a "arreglar".** 23 victorias y 4
        // empates son 73 puntos; con tres descontados por sanción la federación
        // publica 70, y **ésa es la tabla oficial**. Un `CHECK` de aritmética la
        // rechazaría con un `23514` que nadie relaciona con una sanción
        // deportiva, y se perdería la jornada entera.
        try await Self.withSeeded("st-chk-arith") { seeded, tenant in
            try await tenant.scope {
                try await $0.standingRows.save(
                    try Self.row(seeded, won: 23, drawn: 4, lost: 3, points: 70))
            }

            let read = try await tenant.scope {
                try await $0.standingRows.list(roundID: seeded.round)
            }
            #expect(read.first?.points == 70)
        }
    }

    /// Un `INSERT` que **no pasa por el Dominio**, para que los `CHECK` se prueben
    /// por su cuenta y no por la guarda de la entidad.
    ///
    /// Va por `tenant.raw` —fuera de todo ámbito y contra el *pool* del plano de
    /// control— porque es justamente la vía que un *script* o una migración futura
    /// usarían para esquivar la entidad. Por eso la tabla se cualifica con el
    /// *schema*: aquí no hay `search_path` (§6.2).
    static func insertRaw(
        position: Int, points: Int, seeded: Seeded, on tenant: TenantFixture
    ) async throws {
        try await tenant.raw.raw("""
            INSERT INTO \(ident: tenant.schema).standing_rows
              (id, competition_id, round_id, team_id, position, played, won, drawn,
               lost, goals_for, goals_against, points, created_at, updated_at)
            VALUES (\(bind: UUID()), \(bind: seeded.competition.raw),
                    \(bind: seeded.round.raw), \(bind: seeded.teamA.raw),
                    \(bind: position), 30, 23, 4, 3, 78, 23, \(bind: points),
                    now(), now())
            """).run()
    }
}
