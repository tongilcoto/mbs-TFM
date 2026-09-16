import Domain
import Foundation
import Testing

@testable import Application

/// Nivel 2 (§8.1): **la pasada de clasificación**, con los puertos falseados y
/// cero I/O.
///
/// Lo que **no** se prueba aquí: la aritmética de la tabla, el orden y la columna
/// PREV —son de nivel 1 y están cubiertos (`StandingTableTests`,
/// `StandingPreviousPositionTests`)— ni qué jornadas entran, que es
/// `StandingsSyncPlanTests`. Lo que sí: **la orquestación** — qué se pide, qué se
/// escribe, qué se deja registrado y qué pasa con lo que no casa.
///
/// # La unidad es la jornada, y de ahí sale casi todo lo de abajo
///
/// El calendario es agnóstico de jornada porque su endpoint devuelve la
/// competición entera en una petición; `/api/standings?round=N` sirve **una**.
/// Así que una pasada **es** una jornada, deja **una** fila en `ingestion_runs`
/// con su `round_id`, y un alta en la jornada 10 deja diez.
@Suite("IngestStandings · §2.3-b · la pasada de clasificación")
struct IngestStandingsTests {

    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    // ── Andamiaje ────────────────────────────────────────────────────────────

    /// Devuelve la tabla que se le dé **por jornada**, y apunta qué le pidieron.
    final class StandingsClient: FederationClient, @unchecked Sendable {
        private let tables: [Int: FederationStanding]
        private let error: (any Error)?
        private(set) var asked: [(coordinate: FederationCoordinate, round: Int)] = []

        init(_ tables: [Int: FederationStanding], failingWith error: (any Error)? = nil) {
            self.tables = tables
            self.error = error
        }

        func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar {
            throw StandingsNotStubbed(client: "StandingsClient")
        }

        func fetchStandings(
            _ coordinate: FederationCoordinate, round: Int
        ) async throws -> FederationStanding {
            asked.append((coordinate, round))
            if let error { throw error }
            guard let table = tables[round] else {
                throw FederationError.coordinateNotFound(detail: "jornada \(round) sin preparar")
            }
            return table
        }
    }

    struct Fixture: Sendable {
        let store: IngestionStore
        let competition: CompetitionID
        let rounds: [Int: RoundID]
        let teams: [String: TeamID]
    }

    /// Siembra un club de la RFFM con una competición, sus jornadas, sus equipos
    /// y sus partidos.
    static func seed(
        federation: FederationCode = .rffm,
        roundNumbers: [Int],
        played: Set<Int>
    ) async throws -> Fixture {
        let store = IngestionStore()
        let season = try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"),
            federationSeasonID: "21", createdAt: now, updatedAt: now)
        let competition = try Competition(
            id: CompetitionID(raw: UUID()), seasonID: season.id,
            modality: .futbol11, gender: .masculino,
            federationCompetitionID: "24037548", federationGroupID: "24037549",
            ageCategory: .cadete, divisionLabel: "Primera División Autonómica",
            groupLabel: "Grupo 1", createdAt: now, updatedAt: now)

        var teams: [String: TeamID] = [:]
        var teamEntities: [Team] = []
        for code in ["111", "222"] {
            let club = try OpponentClub(
                id: OpponentClubID(raw: UUID()), name: "CLUB \(code)",
                shortName: "CLUB \(code)", slug: try Slug("club-\(code)"),
                createdAt: now, updatedAt: now)
            let team = try Team(
                id: TeamID(raw: UUID()), opponentClubID: club.id, category: .cadete,
                letter: code == "111" ? "A" : "B", gender: .masculino,
                modality: .futbol11, federationTeamID: code,
                createdAt: now, updatedAt: now)
            teams[code] = team.id
            teamEntities.append(team)
            await store.seed(opponentClubs: [club])
        }

        var rounds: [Int: RoundID] = [:]
        var roundEntities: [Round] = []
        var matches: [Match] = []
        for number in roundNumbers {
            let round = try Round(
                id: RoundID(raw: UUID()), competitionID: competition.id, number: number,
                startDate: now, endDate: now, createdAt: now, updatedAt: now)
            rounds[number] = round.id
            roundEntities.append(round)
            matches.append(
                try Match(
                    id: MatchID(raw: UUID()), competitionID: competition.id,
                    roundID: round.id,
                    kickoff: try Kickoff(date: now),
                    homeTeamID: try #require(teams["111"]),
                    awayTeamID: try #require(teams["222"]),
                    result: played.contains(number)
                        ? try MatchResult(homeScore: 2, awayScore: 0) : nil,
                    status: .programado, createdAt: now, updatedAt: now))
        }

        await store.seed(club: try Club(
            id: ClubID(raw: UUID()), name: "Atleti", shortName: "Atleti",
            slug: try Slug("atleti"),
            federation: federation, createdAt: now, updatedAt: now))
        await store.seed(
            seasons: [season], competitions: [competition], rounds: roundEntities,
            teams: teamEntities, matches: matches)

        return Fixture(
            store: store, competition: competition.id, rounds: rounds, teams: teams)
    }

    static func table(_ codes: [String]) -> FederationStanding {
        FederationStanding(
            federationCompetitionID: "24037548",
            competitionName: "PRIMERA DIVISION AUTONOMICA CADETE",
            rows: codes.enumerated().map { index, code in
                FederationStandingRow(
                    team: FederationTeamRef(
                        federationTeamID: code, name: "CLUB \(code)", letter: nil,
                        federationClubID: nil, crestURL: nil),
                    position: index + 1, played: 1,
                    won: index == 0 ? 1 : 0, drawn: 0, lost: index == 0 ? 0 : 1,
                    goalsFor: index == 0 ? 2 : 0, goalsAgainst: index == 0 ? 0 : 2,
                    points: index == 0 ? 3 : 0)
            })
    }

    static func useCase(
        _ fixture: Fixture, client: any FederationClient, clock: (any Clock)? = nil
    ) -> IngestStandings {
        IngestStandings(
            unitOfWork: FakeUnitOfWork(store: fixture.store),
            federation: client,
            clock: clock ?? FixedClock(instant: now),
            ids: SequentialUUIDProvider())
    }

    // ── Lo que pide ──────────────────────────────────────────────────────────

    @Test("pide la clasificación con la coordenada del club y la jornada (§F.8)")
    func itAsksWithTheCoordinateAndTheRound() async throws {
        let fixture = try await Self.seed(roundNumbers: [1], played: [1])
        let client = StandingsClient([1: Self.table(["111", "222"])])

        _ = try await Self.useCase(fixture, client: client)
            .execute(competitionID: fixture.competition, actor: .init(clubSlug: try Slug("atleti")))

        #expect(client.asked.count == 1)
        #expect(client.asked.first?.round == 1)
        #expect(client.asked.first?.coordinate.federationGroupID == "24037549")
    }

    @Test("un alta a mitad de temporada recompone las jornadas anteriores (D-55)")
    func amidSeasonSignUpBackfills() async throws {
        let fixture = try await Self.seed(roundNumbers: [1, 2, 3], played: [1, 2, 3])
        let client = StandingsClient([
            1: Self.table(["111", "222"]), 2: Self.table(["111", "222"]),
            3: Self.table(["222", "111"]),
        ])

        let runs = try await Self.useCase(fixture, client: client)
            .execute(competitionID: fixture.competition, actor: .init(clubSlug: try Slug("atleti")))

        // Tres peticiones, tres jornadas escritas y **tres filas de registro**,
        // cada una con su jornada: sin `round_id` serían tres filas idénticas.
        #expect(client.asked.map(\.round) == [1, 2, 3])
        #expect(runs.count == 3)
        #expect(runs.allSatisfy { $0.kind == .standings })
        #expect(runs.compactMap(\.roundID).count == 3)
        #expect(Set(runs.compactMap(\.roundID)).count == 3)
    }

    @Test("cada jornada escribe una fila por equipo (§3.5)")
    func eachRoundWritesARowPerTeam() async throws {
        let fixture = try await Self.seed(roundNumbers: [1, 2], played: [1, 2])
        let client = StandingsClient([
            1: Self.table(["111", "222"]), 2: Self.table(["222", "111"]),
        ])

        _ = try await Self.useCase(fixture, client: client)
            .execute(competitionID: fixture.competition, actor: .init(clubSlug: try Slug("atleti")))

        let written = await fixture.store.standingRows
        #expect(written.count == 4)
        #expect(Set(written.map(\.roundID)).count == 2)
        // El orden que publica la fuente se respeta: en la jornada 2 gana el otro.
        let second = written.filter { $0.roundID == fixture.rounds[2] }
        #expect(second.first { $0.position == 1 }?.teamID == fixture.teams["222"])
    }

    // ── La columna PREV, encadenada jornada a jornada ────────────────────────

    @Test("la primera jornada no tiene PREV, y la segunda la tiene de la primera (D-33)")
    func prevIsChainedAcrossRounds() async throws {
        let fixture = try await Self.seed(roundNumbers: [1, 2], played: [1, 2])
        let client = StandingsClient([
            1: Self.table(["111", "222"]), 2: Self.table(["222", "111"]),
        ])

        _ = try await Self.useCase(fixture, client: client)
            .execute(competitionID: fixture.competition, actor: .init(clubSlug: try Slug("atleti")))

        let written = await fixture.store.standingRows
        let first = written.filter { $0.roundID == fixture.rounds[1] }
        let second = written.filter { $0.roundID == fixture.rounds[2] }

        // Es lo que hace que la pantalla pinte flechas: en la jornada 1 no hay
        // anterior con la que comparar, y en la 2 los dos equipos se cruzan.
        #expect(first.allSatisfy { $0.previousPosition == nil })
        #expect(second.first { $0.teamID == fixture.teams["222"] }?.previousPosition == 2)
        #expect(second.first { $0.teamID == fixture.teams["111"] }?.previousPosition == 1)
    }

    // ── El *fallback* de D-15 ────────────────────────────────────────────────

    @Test("con una federación que no sirve jornadas pasadas, lo anterior se calcula (D-15, D-55)")
    func theFallbackComputesThePastForACurrentOnlyProvider() async throws {
        let fixture = try await Self.seed(
            federation: .fcf, roundNumbers: [1, 2], played: [1, 2])
        // Solo la última está preparada: si el caso de uso pidiera las dos,
        // fallaría — que es justo lo que queremos que no haga.
        let client = StandingsClient([2: Self.table(["111", "222"])])

        _ = try await Self.useCase(fixture, client: client)
            .execute(competitionID: fixture.competition, actor: .init(clubSlug: try Slug("atleti")))

        #expect(client.asked.map(\.round) == [2])

        // Y la jornada 1, aun sin pedirse, **está escrita**: calculada desde los
        // partidos. `D-15` dice que la fila existe siempre.
        let first = await fixture.store.standingRows.filter { $0.roundID == fixture.rounds[1] }
        #expect(first.count == 2)
        #expect(first.first { $0.position == 1 }?.teamID == fixture.teams["111"])
        #expect(first.first { $0.position == 1 }?.points == 3)
    }

    // ── Lo que no casa ───────────────────────────────────────────────────────

    @Test("una fila de un equipo desconocido se descarta y se apunta, no revienta")
    func arowOfAnUnknownTeamIsSkipped() async throws {
        let fixture = try await Self.seed(roundNumbers: [1], played: [1])
        // `999` no está en la base: la tabla lo trae porque el calendario aún no
        // ha ingerido las jornadas donde ese equipo juega.
        let client = StandingsClient([1: Self.table(["111", "999"])])

        let runs = try await Self.useCase(fixture, client: client)
            .execute(competitionID: fixture.competition, actor: .init(clubSlug: try Slug("atleti")))

        // La pasada **no falla** (`D-83`): es una fila menos en una tabla, y la
        // pasada siguiente —con el calendario al día— la resuelve sola.
        #expect(runs.first?.outcome == .succeeded)
        #expect(runs.first?.skipped.map(\.reason) == [.unknownStandingTeam])
        #expect(await fixture.store.standingRows.count == 1)
    }

    // ── El registro ──────────────────────────────────────────────────────────

    @Test("la pasada deja su fila con la jornada y los contadores (D-85)")
    func therunRecordsItsRoundAndCounters() async throws {
        let fixture = try await Self.seed(roundNumbers: [1], played: [1])
        let client = StandingsClient([1: Self.table(["111", "222"])])

        let runs = try await Self.useCase(fixture, client: client)
            .execute(competitionID: fixture.competition, actor: .init(clubSlug: try Slug("atleti")))

        let run = try #require(runs.first)
        #expect(run.kind == .standings)
        #expect(run.roundID == fixture.rounds[1])
        #expect(run.standingRowsCreated == 2)
        #expect(run.standingRowsUpdated == 0)
        // Los ocho del calendario van a cero, y `kind` es lo que dice que no
        // aplican en vez de que no se hiciera nada.
        #expect(run.matchesCreated == 0)
        #expect(await fixture.store.ingestionRuns.count == 1)
    }

    @Test("refrescar una jornada ya escrita actualiza, no duplica")
    func refreshingARoundUpdatesInPlace() async throws {
        let fixture = try await Self.seed(roundNumbers: [1], played: [1])
        let client = StandingsClient([1: Self.table(["111", "222"])])
        let actor = ActorContext(clubSlug: try Slug("atleti"))

        _ = try await Self.useCase(fixture, client: client)
            .execute(competitionID: fixture.competition, actor: actor)
        let second = try await Self.useCase(fixture, client: client)
            .execute(competitionID: fixture.competition, actor: actor)

        // La última jugada se refresca siempre (`StandingsSyncPlan`), así que la
        // segunda pasada la vuelve a escribir — pero **sobre la misma fila**: el
        // `UNIQUE(round_id, team_id)` es la identidad.
        #expect(await fixture.store.standingRows.count == 2)
        #expect(second.first?.standingRowsCreated == 0)
        #expect(second.first?.standingRowsUpdated == 2)
    }

    @Test("una jornada que falla deja constancia y no se traga el error (D-85, D-83)")
    func afailedRoundIsRecorded() async throws {
        let fixture = try await Self.seed(roundNumbers: [1], played: [1])
        let client = StandingsClient([:], failingWith: FederationError.unexpectedStatus(
            status: 500, url: "https://www.rffm.es/api/standings"))

        await #expect(throws: (any Error).self) {
            _ = try await Self.useCase(fixture, client: client)
                .execute(
                    competitionID: fixture.competition,
                    actor: .init(clubSlug: try Slug("atleti")))
        }

        // La constancia se escribe **fuera** de la transacción que se deshizo
        // (`D-85`), que es la única forma de que sobreviva la pasada que falla —
        // la única que nadie ve, porque no hay usuario delante.
        let runs = await fixture.store.ingestionRuns
        #expect(runs.count == 1)
        #expect(runs.first?.outcome == .failed)
        #expect(runs.first?.kind == .standings)
        #expect(runs.first?.roundID == fixture.rounds[1])
        #expect(runs.first?.error?.isEmpty == false)
    }

    @Test("la PREV de un refresco sale del *snapshot* guardado, no de la nada (D-33)")
    func prevComesFromTheStoredEarlierRound() async throws {
        // **El caso semanal, que es el 99% de las pasadas.** Las jornadas
        // anteriores ya están escritas de semanas pasadas, así que la única que
        // se sincroniza es la última — y su columna PREV **no puede salir de esta
        // pasada**: tiene que leerse de lo guardado. Sin eso, la pantalla
        // perdería las flechas justo en la jornada que la gente mira.
        let fixture = try await Self.seed(roundNumbers: [1, 2], played: [1, 2])
        let round1 = try #require(fixture.rounds[1])
        // La jornada 1, ya guardada: `111` primero, `222` segundo.
        await fixture.store.seed(standingRows: [
            try StandingRow(
                id: StandingRowID(raw: UUID()), competitionID: fixture.competition,
                roundID: round1, teamID: try #require(fixture.teams["111"]),
                position: 1, played: 1, won: 1, drawn: 0, lost: 0,
                goalsFor: 2, goalsAgainst: 0, points: 3,
                createdAt: Self.now, updatedAt: Self.now),
            try StandingRow(
                id: StandingRowID(raw: UUID()), competitionID: fixture.competition,
                roundID: round1, teamID: try #require(fixture.teams["222"]),
                position: 2, played: 1, won: 0, drawn: 0, lost: 1,
                goalsFor: 0, goalsAgainst: 2, points: 0,
                createdAt: Self.now, updatedAt: Self.now),
        ])

        // En la jornada 2 se cruzan.
        let client = StandingsClient([2: Self.table(["222", "111"])])
        _ = try await Self.useCase(fixture, client: client)
            .execute(competitionID: fixture.competition, actor: .init(clubSlug: try Slug("atleti")))

        #expect(client.asked.map(\.round) == [2])
        let second = await fixture.store.standingRows.filter { $0.roundID == fixture.rounds[2] }
        #expect(second.first { $0.teamID == fixture.teams["222"] }?.previousPosition == 2)
        #expect(second.first { $0.teamID == fixture.teams["111"] }?.previousPosition == 1)
    }

    @Test("la pasada mide su duración, y hace falta un reloj que ande (F6)")
    func therunMeasuresItsDuration() async throws {
        // **Con `FixedClock` este test no dice nada**, y por eso va con
        // `TickingClock`: empezar y terminar serían el mismo instante y un
        // cronómetro roto pasaría. Es el defecto que F6 solo encontró ejecutando
        // el sistema contra la base de verdad —toda pasada con éxito registraba
        // 0,00 s— y el doble existe justamente para que no vuelva a hacer falta
        // mirarlo a mano.
        let fixture = try await Self.seed(roundNumbers: [1], played: [1])
        let client = StandingsClient([1: Self.table(["111", "222"])])

        let runs = try await Self.useCase(
            fixture, client: client, clock: TickingClock(from: Self.now)
        ).execute(competitionID: fixture.competition, actor: .init(clubSlug: try Slug("atleti")))

        let run = try #require(runs.first)
        #expect(run.finishedAt > run.startedAt)
    }

    @Test("sin jornadas jugadas no hay pasada, y no es un error")
    func nothingPlayedIsNoRun() async throws {
        let fixture = try await Self.seed(roundNumbers: [1, 2], played: [])
        let client = StandingsClient([:])

        let runs = try await Self.useCase(fixture, client: client)
            .execute(competitionID: fixture.competition, actor: .init(clubSlug: try Slug("atleti")))

        // Una competición dada de alta en agosto: el calendario sí tiene trabajo
        // —trae los partidos sin jugar— y ésta no.
        #expect(runs.isEmpty)
        #expect(client.asked.isEmpty)
        #expect(await fixture.store.ingestionRuns.isEmpty)
    }
}
