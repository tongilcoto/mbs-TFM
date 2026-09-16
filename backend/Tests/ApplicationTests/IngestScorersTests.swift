import Domain
import Foundation
import Testing

@testable import Application

/// Nivel 2 (§8.1): **la pasada de goleadores**, con los puertos falseados. Sin
/// I/O, con reloj e ids fijos.
///
/// # Lo que esta suite fija, y en qué NO se parece a la de clasificación
///
/// | | `IngestStandings` (F7) | `IngestScorers` (F8) |
/// |---|---|---|
/// | Unidad de la pasada | **la jornada** | **la competición** |
/// | Filas en `ingestion_runs` | una por jornada | **una** |
/// | `roundID` del registro | obligatorio | **nulo** |
/// | *Fallback* si la fuente no da | se calcula (`D-15`) | **no hay** (`D-48`) |
/// | Lo que sobra | se queda (`D-75`) | **se retira** (`D-94`) |
///
/// Las dos últimas filas son las que importan y las que tienen más tests: una es
/// la capacidad que **no se puede ignorar**, y la otra es la única operación de
/// borrado de toda la salida de la ingesta.
@Suite("IngestScorers · la pasada de goleadores (F8, D-09, D-93, D-94)")
struct IngestScorersTests {

    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    // ── Andamiaje ────────────────────────────────────────────────────────────

    /// Devuelve el ranking que se le dé, y apunta con qué coordenada se le llamó.
    final class ScorersClient: FederationClient, @unchecked Sendable {
        private let table: FederationScorerTable?
        private let error: (any Error)?
        private(set) var asked: [FederationCoordinate] = []

        init(_ table: FederationScorerTable?, failingWith error: (any Error)? = nil) {
            self.table = table
            self.error = error
        }

        func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar {
            throw NotStubbed(client: "ScorersClient", operation: "fetchCalendar")
        }

        func fetchStandings(
            _ coordinate: FederationCoordinate, round: Int
        ) async throws -> FederationStanding {
            throw NotStubbed(client: "ScorersClient", operation: "fetchStandings")
        }

        func fetchScorers(
            _ coordinate: FederationCoordinate
        ) async throws -> FederationScorerTable {
            asked.append(coordinate)
            if let error { throw error }
            guard let table else {
                throw FederationError.coordinateNotFound(detail: "sin preparar")
            }
            return table
        }
    }

    struct Fixture: Sendable {
        let store: IngestionStore
        let competition: CompetitionID
    }

    static func seed(
        federation: FederationCode = .rffm,
        competitionName: String? = nil,
        scorers: [LeagueScorer] = []
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
            groupLabel: "Grupo 1", federationName: competitionName,
            createdAt: now, updatedAt: now)

        await store.seed(club: try Club(
            id: ClubID(raw: UUID()), name: "Atleti", shortName: "Atleti",
            slug: try Slug("atleti"),
            federation: federation, createdAt: now, updatedAt: now))
        await store.seed(
            seasons: [season], competitions: [competition], leagueScorers: scorers)

        return Fixture(store: store, competition: competition.id)
    }

    static func useCase(
        _ fixture: Fixture, client: ScorersClient, clock: (any Clock)? = nil
    ) -> IngestScorers {
        IngestScorers(
            unitOfWork: FakeUnitOfWork(store: fixture.store),
            federation: client,
            clock: clock ?? FixedClock(instant: now),
            ids: SequentialUUIDProvider())
    }

    static let actor = ActorContext(clubSlug: try! Slug("atleti"), isSystem: true)

    /// El reloj de **la pasada siguiente**, una semana después.
    ///
    /// No es decoración: la retirada de `D-94` compara la marca de cada fila con
    /// la de la pasada en curso, así que dos pasadas que compartieran instante no
    /// retirarían nada. Con `FixedClock(instant: now)` en las dos, el test decía
    /// *"no retira"* y el fallo era del andamiaje — la cadencia real de §5.6 es
    /// semanal, no simultánea.
    static func nextWeek() -> TickingClock {
        TickingClock(from: now.addingTimeInterval(7 * 86_400))
    }

    static func row(
        _ id: String, _ name: String, goals: Int, team: String = "EQUIPO A", rank: Int? = nil
    ) -> FederationScorerRow {
        FederationScorerRow(
            federationPlayerID: id, fullName: name, teamLabel: team,
            goals: goals, rank: rank)
    }

    static func table(
        _ rows: [FederationScorerRow], competitionName: String? = nil
    ) -> FederationScorerTable {
        FederationScorerTable(competitionName: competitionName, rows: rows)
    }

    /// Los goleadores que hay guardados, en el orden del repositorio.
    static func stored(_ fixture: Fixture) async throws -> [LeagueScorer] {
        try await FakeLeagueScorerRepository(store: fixture.store)
            .list(competitionID: fixture.competition)
    }

    // ── La pasada, de punta a punta ──────────────────────────────────────────

    @Test("escribe el ranking y deja UNA fila en el registro, sin jornada (§3.2, D-85)")
    func writesTheRankingAndRecordsOneRun() async throws {
        let fixture = try await Self.seed()
        let client = ScorersClient(
            Self.table([
                Self.row("11322891", "GEA IRISARRI, LUIS", goals: 31),
                Self.row("4945003", "BRUZZI, DIEGO", goals: 22),
            ]))

        let run = try #require(
            try await Self.useCase(fixture, client: client)
                .execute(competitionID: fixture.competition, actor: Self.actor))

        #expect(try await Self.stored(fixture).count == 2)

        // **Una fila y no dos ni diez**, que es la asimetría con la clasificación:
        // el endpoint devuelve la competición entera en una petición, así que la
        // pasada es la competición.
        #expect(await fixture.store.ingestionRuns.count == 1)
        #expect(run.kind == .scorers)

        // **Nula, y el `CHECK` del esquema lo repite**: `LeagueScorer` es estado
        // vigente único, no *snapshot* por jornada (§3.2).
        #expect(run.roundID == nil)
        #expect(run.leagueScorersCreated == 2)
        #expect(run.leagueScorersUpdated == 0)
        #expect(run.leagueScorersRetired == 0)
    }

    @Test("llama a la federación con la coordenada de la competición, sin jornada (F8)")
    func callsWithTheCompetitionCoordinate() async throws {
        let fixture = try await Self.seed()
        let client = ScorersClient(Self.table([Self.row("1", "A", goals: 3)]))

        _ = try await Self.useCase(fixture, client: client)
            .execute(competitionID: fixture.competition, actor: Self.actor)

        #expect(client.asked.count == 1)
        #expect(client.asked.first?.federationGroupID == "24037549")
        #expect(client.asked.first?.federationCompetitionID == "24037548")
    }

    // ── El upsert por la clave de D-93 ───────────────────────────────────────

    @Test("la segunda pasada actualiza en vez de duplicar, y la clave es el id de federación (D-93)")
    func theSecondPassUpdatesInsteadOfDuplicating() async throws {
        let fixture = try await Self.seed()
        let first = ScorersClient(Self.table([Self.row("77", "PEREZ, JUAN", goals: 10)]))
        _ = try await Self.useCase(fixture, client: first)
            .execute(competitionID: fixture.competition, actor: Self.actor)

        let second = ScorersClient(Self.table([Self.row("77", "PEREZ, JUAN", goals: 12)]))
        let run = try #require(
            try await Self.useCase(fixture, client: second)
                .execute(competitionID: fixture.competition, actor: Self.actor))

        let stored = try await Self.stored(fixture)
        #expect(stored.count == 1)
        #expect(stored.first?.goals == 12)
        #expect(run.leagueScorersCreated == 0)
        #expect(run.leagueScorersUpdated == 1)
    }

    @Test("dos jugadores con el MISMO nombre son dos filas, que es el argumento de D-93")
    func twoPlayersWithTheSameNameAreTwoRows() async throws {
        let fixture = try await Self.seed()
        let client = ScorersClient(
            Self.table([
                Self.row("77", "GARCIA, JAVIER", goals: 9, team: "EQUIPO A"),
                Self.row("88", "GARCIA, JAVIER", goals: 7, team: "EQUIPO A"),
            ]))

        _ = try await Self.useCase(fixture, client: client)
            .execute(competitionID: fixture.competition, actor: Self.actor)

        // Con la clave alternativa —(competición, nombre, equipo)— estas dos
        // colapsarían en una y el segundo pisaría al primero cada semana. El
        // *spec* lo dice en la descripción del `id`: *"`fullName` no es
        // identificador: dos jugadores pueden llamarse igual"*.
        #expect(try await Self.stored(fixture).count == 2)
    }

    @Test("un jugador que cambia de equipo se ACTUALIZA, no se duplica (D-93)")
    func aPlayerWhoChangesTeamIsUpdated() async throws {
        let fixture = try await Self.seed()
        _ = try await Self.useCase(
            fixture, client: ScorersClient(
                Self.table([Self.row("77", "PEREZ, JUAN", goals: 10, team: "EQUIPO A")])))
            .execute(competitionID: fixture.competition, actor: Self.actor)

        _ = try await Self.useCase(
            fixture, client: ScorersClient(
                Self.table([Self.row("77", "PEREZ, JUAN", goals: 11, team: "EQUIPO B")])))
            .execute(competitionID: fixture.competition, actor: Self.actor)

        let stored = try await Self.stored(fixture)
        #expect(stored.count == 1)
        #expect(stored.first?.teamLabel == "EQUIPO B")
    }

    // ── La retirada (D-94) ───────────────────────────────────────────────────

    @Test("el que deja de publicarse SE RETIRA, y es la única salida de la ingesta que borra (D-94)")
    func whoeverStopsBeingPublishedIsRetired() async throws {
        let fixture = try await Self.seed()
        _ = try await Self.useCase(
            fixture, client: ScorersClient(
                Self.table([
                    Self.row("77", "SIGUE, ANA", goals: 10),
                    Self.row("88", "DESAPARECE, LUIS", goals: 9),
                ])))
            .execute(competitionID: fixture.competition, actor: Self.actor)

        // La segunda pasada solo trae a uno. El otro no es un dato viejo
        // identificable: sería una fila indistinguible de las buenas dentro de
        // una tabla que dice ser la de ahora.
        let run = try #require(
            try await Self.useCase(
                fixture, client: ScorersClient(
                    Self.table([Self.row("77", "SIGUE, ANA", goals: 11)])),
                clock: Self.nextWeek())
                .execute(competitionID: fixture.competition, actor: Self.actor))

        let stored = try await Self.stored(fixture)
        #expect(stored.count == 1)
        #expect(stored.first?.federationPlayerID == "77")
        #expect(run.leagueScorersRetired == 1)
    }

    @Test("y la retirada NO toca las otras competiciones (D-94)")
    func retiringDoesNotTouchOtherCompetitions() async throws {
        let fixture = try await Self.seed()
        // Un goleador de **otra** competición, con marca antigua: es justo el que
        // un `WHERE` sin `competition_id` se llevaría por delante. El fallo no
        // daría error: se vería tres días después, en la pantalla equivocada.
        let alien = try LeagueScorer(
            id: LeagueScorerID(raw: UUID()),
            competitionID: CompetitionID(raw: UUID()),
            federationPlayerID: "999", fullName: "AJENO, PEDRO", teamLabel: "OTRA LIGA",
            goals: 40, syncedAt: Self.now.addingTimeInterval(-86_400),
            createdAt: Self.now, updatedAt: Self.now)
        await fixture.store.seed(leagueScorers: [alien])

        _ = try await Self.useCase(
            fixture, client: ScorersClient(Self.table([Self.row("77", "PROPIO, ANA", goals: 3)])),
            clock: Self.nextWeek())
            .execute(competitionID: fixture.competition, actor: Self.actor)

        #expect(await fixture.store.leagueScorers.contains { $0.id == alien.id },
                "la retirada se llevó un goleador de otra competición")
    }

    @Test("una pasada que no retira nada deja el contador a cero (D-94)")
    func aPassThatRetiresNothingCountsZero() async throws {
        let fixture = try await Self.seed()
        _ = try await Self.useCase(
            fixture, client: ScorersClient(Self.table([Self.row("77", "A", goals: 3)])))
            .execute(competitionID: fixture.competition, actor: Self.actor)

        let run = try #require(
            try await Self.useCase(
                fixture, client: ScorersClient(Self.table([Self.row("77", "A", goals: 4)])),
                clock: Self.nextWeek())
                .execute(competitionID: fixture.competition, actor: Self.actor))

        #expect(run.leagueScorersRetired == 0)
    }

    // ── La capacidad que no se puede ignorar (D-48) ──────────────────────────

    @Test("con una federación que no publica goleadores NO se llama a la fuente (D-48)")
    func aFederationWithoutScorersIsNotAsked() async throws {
        // Hoy las dos publican, así que esta guarda no se dispara con datos
        // reales. Se prueba con un catálogo falseado porque la regla existe para
        // la tercera federación, y `D-48` dice que con `false` la tabla queda
        // **vacía para siempre**: no hay *fallback* posible (`D-09`).
        let fixture = try await Self.seed()
        let client = ScorersClient(Self.table([Self.row("1", "A", goals: 3)]))

        let run = try await IngestScorers(
            unitOfWork: FakeUnitOfWork(store: fixture.store),
            federation: client,
            clock: FixedClock(instant: Self.now),
            ids: SequentialUUIDProvider(),
            capabilities: { _ in
                FederationCapabilities(providesRoundStandings: true, providesScorers: false)
            })
            .execute(competitionID: fixture.competition, actor: Self.actor)

        #expect(run == nil, "sin capacidad no hay pasada que registrar")
        #expect(client.asked.isEmpty, "se llamó a una fuente que no publica goleadores")
        #expect(try await Self.stored(fixture).isEmpty)
    }

    @Test("y esa guarda tampoco RETIRA nada: sin dato, la tabla se queda como esté (D-48)")
    func theCapabilityGuardDoesNotRetireEither() async throws {
        // El borde que se cuela solo: si la guarda cortara *después* de decidir
        // retirar, apagar la capacidad de una federación vaciaría los rankings ya
        // ingeridos. `D-48` dice *"no hay dato"*, no *"borra el que había"*.
        let existing = try LeagueScorer(
            id: LeagueScorerID(raw: UUID()),
            competitionID: CompetitionID(raw: UUID()),
            federationPlayerID: "5", fullName: "YA ESTABA, LUIS", teamLabel: "EQ",
            goals: 12, syncedAt: Self.now, createdAt: Self.now, updatedAt: Self.now)
        let fixture = try await Self.seed(scorers: [existing])

        _ = try await IngestScorers(
            unitOfWork: FakeUnitOfWork(store: fixture.store),
            federation: ScorersClient(Self.table([])),
            clock: FixedClock(instant: Self.now),
            ids: SequentialUUIDProvider(),
            capabilities: { _ in
                FederationCapabilities(providesRoundStandings: true, providesScorers: false)
            })
            .execute(competitionID: fixture.competition, actor: Self.actor)

        #expect(await fixture.store.leagueScorers.count == 1)
    }

    // ── La guarda de la coordenada (D-84) ────────────────────────────────────

    @Test("si el nombre de la competición no casa, la pasada falla (D-84)")
    func aMismatchedCompetitionNameFailsThePass() async throws {
        let fixture = try await Self.seed(
            competitionName: "PRIMERA DIVISION AUTONOMICA CADETE")
        let client = ScorersClient(
            Self.table([Self.row("1", "A", goals: 3)], competitionName: "PREFERENTE AFICIONADO"))

        await #expect(throws: (any Error).self) {
            try await Self.useCase(fixture, client: client)
                .execute(competitionID: fixture.competition, actor: Self.actor)
        }
        #expect(try await Self.stored(fixture).isEmpty,
                "se escribieron goleadores de otra competición")
    }

    @Test("y el fallo deja su fila en el registro, fuera de la transacción (D-85)")
    func theFailureLeavesItsRecord() async throws {
        let fixture = try await Self.seed(
            competitionName: "PRIMERA DIVISION AUTONOMICA CADETE")
        let client = ScorersClient(
            Self.table([Self.row("1", "A", goals: 3)], competitionName: "OTRA COSA"))

        _ = try? await Self.useCase(fixture, client: client)
            .execute(competitionID: fixture.competition, actor: Self.actor)

        let runs = await fixture.store.ingestionRuns
        #expect(runs.count == 1)
        #expect(runs.first?.outcome == .failed)
        #expect(runs.first?.kind == .scorers)
        #expect(runs.first?.error != nil)
    }

    @Test("una coordenada que no designa nada también deja constancia (D-84, D-85)")
    func anUnknownCoordinateIsRecordedToo() async throws {
        let fixture = try await Self.seed()
        let client = ScorersClient(
            nil, failingWith: FederationError.coordinateNotFound(detail: "null"))

        _ = try? await Self.useCase(fixture, client: client)
            .execute(competitionID: fixture.competition, actor: Self.actor)

        let runs = await fixture.store.ingestionRuns
        #expect(runs.count == 1)
        #expect(runs.first?.outcome == .failed)
    }

    // ── Lo que no se puede construir se descarta y se apunta ─────────────────

    @Test("una fila sin identificador se descarta y se apunta, sin tirar el ranking (D-86)")
    func anUnidentifiedRowIsSkipped() async throws {
        let fixture = try await Self.seed()
        let client = ScorersClient(
            Self.table([
                FederationScorerRow(
                    federationPlayerID: nil, fullName: "SIN CODIGO, A",
                    teamLabel: "EQ", goals: 9),
                Self.row("77", "CON CODIGO, B", goals: 8),
            ]))

        let run = try #require(
            try await Self.useCase(fixture, client: client)
                .execute(competitionID: fixture.competition, actor: Self.actor))

        // 1 de 2 sigue siendo un ranking utilizable: no hay numeración que
        // agujerear, al revés que en la clasificación.
        #expect(try await Self.stored(fixture).count == 1)
        #expect(run.outcome == .succeeded)
        #expect(run.skipped.count == 1)
        #expect(run.skipped.first?.reason == .unidentifiedScorer)

        // **Y el detalle lleva con qué encontrarla en la fuente**, que es para lo
        // que existe el campo: lo lee una persona días después.
        #expect(run.skipped.first?.detail.contains("SIN CODIGO, A") == true)
    }

    @Test("una fila sin goles también se descarta: `nil` no es cero (D-56)")
    func aRowWithoutGoalsIsSkipped() async throws {
        let fixture = try await Self.seed()
        let client = ScorersClient(
            Self.table([
                FederationScorerRow(
                    federationPlayerID: "77", fullName: "SIN GOLES, A",
                    teamLabel: "EQ", goals: nil),
            ]))

        let run = try #require(
            try await Self.useCase(fixture, client: client)
                .execute(competitionID: fixture.competition, actor: Self.actor))

        // Escribir un `0` aquí afirmaría *"este jugador no ha marcado"*, que es un
        // dato; lo que hay es *"la fuente no lo dijo"*. Es `D-56` con la forma que
        // le toca a una tabla que se pisa entera.
        #expect(try await Self.stored(fixture).isEmpty)
        #expect(run.skipped.count == 1)
    }

    @Test("un ranking vacío es una pasada con éxito, no un fallo (D-48)")
    func anEmptyRankingIsASuccess() async throws {
        let fixture = try await Self.seed()
        let run = try #require(
            try await Self.useCase(fixture, client: ScorersClient(Self.table([])))
                .execute(competitionID: fixture.competition, actor: Self.actor))

        // Una liga recién empezada no tiene goleadores, y eso no es un error. El
        // *spec* lo dice: *"lista vacía si la federación no publica goleadores o
        // si la competición aún no se ha sincronizado — no es un error"*.
        #expect(run.outcome == .succeeded)
        #expect(run.leagueScorersCreated == 0)
    }

    // ── El cronómetro (la lección de F6 y F7) ────────────────────────────────

    @Test("la pasada mide su duración de verdad (F6, F7)")
    func theRunMeasuresItsDuration() async throws {
        let fixture = try await Self.seed()
        let run = try #require(
            try await Self.useCase(
                fixture, client: ScorersClient(Self.table([Self.row("1", "A", goals: 3)])),
                clock: Self.nextWeek())
                .execute(competitionID: fixture.competition, actor: Self.actor))

        // Con un reloj fijo, un cronómetro roto pasa el test: `finishedAt ==
        // startedAt` se cumple trivialmente y la invariante del `init` no lo
        // delata. Es el defecto que F6 solo encontró mirando la tabla de verdad, y
        // que en F7 sobrevivió a la primera pasada de mutación.
        #expect(run.finishedAt > run.startedAt)
    }
}
