import Application
import Domain
import Federation
import Fluent
import Foundation
import SQLKit
import Testing
import Vapor

@testable import App
import TestSupport
@testable import Persistence
@testable import Tenancy

/// Nivel 3 (§8.1) y **la rebanada que da nombre a F5**: el volcado real pasa por
/// el parser real (F2), por la cadena real (F4) y por la política real (F3), y
/// acaba en Postgres.
///
/// Lo único falseado es el **transporte**: se le da el fichero en vez de la red.
/// Eso es a propósito — la batería tiene que ser determinista (Plan §4.4), y la
/// pregunta *"¿han cambiado ellos?"* la contesta el canario, no esto.
@Suite("Ingesta end-to-end · §2.3-b · el volcado real hasta Postgres",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct CalendarIngestionEndToEndTests {

    static let prefix = "test_e2e_"
    static let syncInstant = Date(timeIntervalSince1970: 1_790_000_000)

    /// Los volcados viven en `Tests/FederationTests/Fixtures/` y **no se copian
    /// aquí**: son 380 KB cada uno y ya hay dos copias en el repositorio (la de
    /// `docs/`, que es la evidencia, y la del *target* que los empaqueta como
    /// recurso). Una tercera sería la que se queda desfasada.
    ///
    /// Se leen por ruta relativa al fichero fuente, que es lo que permite
    /// compartirlos entre *targets* sin duplicar.
    static func fixture(_ name: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here
            .deletingLastPathComponent()
            .appendingPathComponent("FederationTests/Fixtures/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// El transporte falseado: devuelve el fichero. Es el **único** doble de este
    /// test.
    struct FixtureTransport: FederationTransport {
        let body: String
        func get(_ url: String) async throws -> String { body }
    }

    static func withTenant(
        _ slug: String, _ body: @escaping @Sendable (TenantFixture) async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(
                slug, federation: .rffm, schemaPrefix: prefix, on: app)
            try await body(TenantFixture(app: app, slug: slug, schema: "\(prefix)\(slug)"))
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    /// Siembra la **entrada** de la ingesta (`D-16`) con la coordenada real del
    /// volcado, y devuelve el caso de uso cableado contra Postgres.
    static func prepare(
        _ tenant: TenantFixture, fixture name: String, app: Vapor.Application
    ) async throws -> (IngestCalendar, CompetitionID) {
        let season = try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"),
            federationSeasonID: "21", createdAt: Date(), updatedAt: Date())
        let competition = try Competition(
            id: CompetitionID(raw: UUID()), seasonID: season.id,
            modality: .futbol11, gender: .masculino,
            federationCompetitionID: "24037548", federationGroupID: "24037549",
            ageCategory: .cadete, divisionLabel: "Primera División Autonómica",
            groupLabel: "Grupo 1", createdAt: Date(), updatedAt: Date())
        try await tenant.scope {
            try await $0.seasons.save(season)
            try await $0.competitions.save(competition)
        }

        let useCase = IngestCalendar(
            unitOfWork: FluentTenantUnitOfWork(controlDatabase: app.db(.control)),
            federation: RFFMFederationClient(
                transport: FixtureTransport(body: try fixture(name))),
            clock: FixedInstantClock(instant: syncInstant),
            ids: SystemUUIDProvider())
        return (useCase, competition.id)
    }

    // ── La temporada jugada: 30 jornadas, 240 partidos ─────────────────────

    /// El volcado que Plan §4.3 daba por pendiente, entero. **Los 240 partidos
    /// vienen con marcador y con hora**, así que ésta es la primera vez que la
    /// rama de "partido jugado" se ejercita con dato real de calendario.
    @Test("ingiere el calendario de una temporada jugada de punta a punta (§2.3-b)")
    func ingestsAPlayedSeason() async throws {
        try await Self.withTenant("e2e-jugada") { tenant in
            let (useCase, competitionID) = try await Self.prepare(
                tenant, fixture: "RFFM-calendario-temporada-jugada.html", app: tenant.app)

            let report = try await useCase.execute(
                competitionID: competitionID,
                actor: .init(clubSlug: try Slug("e2e-jugada"), isSystem: true))

            #expect(report.skipped.isEmpty)
            #expect(report.roundsCreated == 30)
            #expect(report.matchesCreated == 240)

            let stored = try await tenant.scope { repositories in
                (rounds: try await repositories.rounds.list(competitionID: competitionID),
                 matches: try await repositories.matches.list(competitionID: competitionID),
                 teams: try await repositories.teams.list(),
                 clubs: try await repositories.opponentClubs.list(),
                 competition: try await repositories.competitions.find(competitionID))
            }

            #expect(stored.rounds.count == 30)
            #expect(stored.matches.count == 240)

            // 16 equipos jugando 30 jornadas a 8 partidos por jornada.
            #expect(stored.teams.count == 16)
            #expect(stored.clubs.count == 16)
            // `D-66`: la ingesta no crea equipos propios. **Los 16 son rivales**.
            #expect(stored.teams.allSatisfy { !$0.isOwn })
            // `D-07`, `D-58`: las tres piezas las presta la competición.
            #expect(stored.teams.allSatisfy {
                $0.category == .cadete && $0.gender == .masculino
                    && $0.modality == .futbol11
            })

            // La rama de "partido jugado", con dato real por primera vez.
            #expect(stored.matches.allSatisfy { $0.result != nil })
            #expect(stored.matches.allSatisfy { $0.status == .finalizado })
            #expect(stored.matches.allSatisfy { $0.isKickoffConfirmed })

            // `D-81` sobre el reparto real: 26 de las 30 jornadas ocupan dos días.
            let twoDaySpans = stored.rounds.filter { $0.startDate != $0.endDate }
            #expect(twoDaySpans.count == 26)

            #expect(stored.competition?.lastSyncedAt == Self.syncInstant)
            #expect(stored.competition?.federationName
                    == "PRIMERA DIVISION AUTONOMICA CADETE")
        }
    }

    // ── La temporada sin arrancar: la otra mitad de cada regla ─────────────

    /// El mismo recorrido sobre el volcado sin arrancar: **306 partidos, ninguno
    /// con marcador y ninguno con hora**. Es lo que demuestra que `D-56` no está
    /// escribiendo ceros ni medianoches.
    ///
    /// Y `D-81` en su otro extremo: los 306 comparten fecha, así que **las 34
    /// jornadas duran un día**. La competición de este volcado es senior y juega
    /// en **domingo**, lo que de paso desmiente el *"el calendario nace en
    /// sábado"* de [Anexo RFFM §F.5].
    @Test("ingiere un calendario sin arrancar sin inventar marcador ni hora (D-56, D-81)")
    func ingestsAnUnstartedSeason() async throws {
        try await Self.withTenant("e2e-sinjugar") { tenant in
            let (useCase, competitionID) = try await Self.prepare(
                tenant, fixture: "RFFM-calendario-temporada-sin-jugar.html",
                app: tenant.app)

            let report = try await useCase.execute(
                competitionID: competitionID,
                actor: .init(clubSlug: try Slug("e2e-sinjugar"), isSystem: true))

            #expect(report.skipped.isEmpty)
            #expect(report.roundsCreated == 34)
            #expect(report.matchesCreated == 306)

            let stored = try await tenant.scope { repositories in
                (rounds: try await repositories.rounds.list(competitionID: competitionID),
                 matches: try await repositories.matches.list(competitionID: competitionID))
            }

            #expect(stored.matches.allSatisfy { $0.result == nil })
            #expect(stored.matches.allSatisfy { $0.status == .programado })
            #expect(stored.matches.allSatisfy { !$0.isKickoffConfirmed })
            #expect(stored.rounds.allSatisfy { $0.startDate == $0.endDate })
        }
    }

    // ── Idempotencia contra las restricciones de verdad ────────────────────

    /// El nivel 2 ya prueba que la segunda pasada no duplica, **pero con dobles
    /// que no tienen restricciones**. Aquí las hay: si la pasada intentara
    /// reinsertar cualquiera de las 240 filas, el `UNIQUE` de §3.5 la pararía y
    /// la transacción entera reventaría.
    ///
    /// Es la diferencia entre "el caso de uso cree que no duplica" y "no
    /// duplica", y es la razón por la que F5 tiene los dos niveles.
    @Test("la segunda pasada no choca con ninguna restricción de §3.5")
    func secondPassIsIdempotentAgainstRealConstraints() async throws {
        try await Self.withTenant("e2e-idem") { tenant in
            let (useCase, competitionID) = try await Self.prepare(
                tenant, fixture: "RFFM-calendario-temporada-jugada.html", app: tenant.app)
            let actor = ActorContext(clubSlug: try Slug("e2e-idem"), isSystem: true)

            _ = try await useCase.execute(competitionID: competitionID, actor: actor)
            let second = try await useCase.execute(competitionID: competitionID, actor: actor)

            #expect(second.matchesCreated == 0)
            #expect(second.roundsCreated == 0)
            #expect(second.opponentClubsCreated == 0)
            #expect(second.teamsCreated == 0)
            #expect(second.skipped.isEmpty)

            let stored = try await tenant.scope { repositories in
                (matches: try await repositories.matches.list(competitionID: competitionID),
                 teams: try await repositories.teams.list())
            }
            #expect(stored.matches.count == 240)
            #expect(stored.teams.count == 16)
        }
    }

    // ── D-83: una pasada, un ámbito, y un fallo no deja nada ───────────────

    /// **La propiedad que el nivel 2 no puede probar**, porque sus dobles no
    /// tienen transacción: cuando algo revienta a mitad de la pasada, lo que ya
    /// se había escrito **se deshace**.
    ///
    /// El fallo se provoca con un partido de un equipo contra sí mismo, que la
    /// invariante de `Match` (§3.5) rechaza. Para cuando eso ocurre, la pasada ya
    /// ha escrito el club, el equipo y la jornada del **primer** partido — así
    /// que si no hubiera transacción, quedarían.
    ///
    /// Y la otra mitad, que es lo que pidió el desarrollador: **no se borra
    /// nada**. La competición sembrada antes de la pasada sigue ahí, y sigue sin
    /// `last_synced_at`, que es como se sabe que la sincronización no tuvo éxito.
    @Test("un fallo a mitad de pasada no deja nada escrito, y no borra lo que había (D-83)")
    func aFailedPassLeavesNothingBehind() async throws {
        try await Self.withTenant("e2e-rollback") { tenant in
            let season = try Season(
                id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"),
                federationSeasonID: "21", createdAt: Date(), updatedAt: Date())
            let competition = try Competition(
                id: CompetitionID(raw: UUID()), seasonID: season.id,
                modality: .futbol11, gender: .masculino,
                federationCompetitionID: "24037548", federationGroupID: "24037549",
                ageCategory: .cadete, divisionLabel: "Primera División Autonómica",
                groupLabel: "Grupo 1", createdAt: Date(), updatedAt: Date())
            try await tenant.scope {
                try await $0.seasons.save(season)
                try await $0.competitions.save(competition)
            }

            let useCase = IngestCalendar(
                unitOfWork: FluentTenantUnitOfWork(controlDatabase: tenant.app.db(.control)),
                federation: StubFederationClient(returning: Self.brokenCalendar()),
                clock: FixedInstantClock(instant: Self.syncInstant),
                ids: SystemUUIDProvider())

            await #expect(throws: DomainError.self) {
                try await useCase.execute(
                    competitionID: competition.id,
                    actor: .init(clubSlug: try Slug("e2e-rollback"), isSystem: true))
            }

            let after = try await tenant.scope { repositories in
                (clubs: try await repositories.opponentClubs.list(),
                 teams: try await repositories.teams.list(),
                 rounds: try await repositories.rounds.list(competitionID: competition.id),
                 matches: try await repositories.matches.list(competitionID: competition.id),
                 competition: try await repositories.competitions.find(competition.id))
            }

            // Nada de la pasada sobrevive, ni siquiera lo del primer partido,
            // que llegó a escribirse antes de que reventara el segundo.
            #expect(after.clubs.isEmpty)
            #expect(after.teams.isEmpty)
            #expect(after.rounds.isEmpty)
            #expect(after.matches.isEmpty)
            // Y nada de lo que había se pierde.
            #expect(after.competition != nil)
            #expect(after.competition?.lastSyncedAt == nil)
        }
    }

    // ── D-85: el registro sobrevive a lo que la pasada no ──────────────────

    /// **La prueba que justifica que el registro vaya en su propio ámbito.**
    ///
    /// El nivel 2 puede afirmar que se llama a `record`, pero no que la fila
    /// sobreviva: sus dobles no tienen transacción. Aquí sí. La pasada revienta a
    /// mitad, el `rollback` se lleva clubes, equipos, jornadas y partidos — **y el
    /// registro se queda**, que es el único sitio donde va a constar que esa noche
    /// la ingesta falló.
    ///
    /// Si el `record` viviera dentro del ámbito de escritura, este test pasaría
    /// en el nivel 2 y fallaría aquí. Es exactamente la clase de cosa que Plan §5
    /// pone en el nivel 3.
    @Test("el registro de la pasada fallida sobrevive al rollback (D-85)")
    func theRunRecordSurvivesTheRollback() async throws {
        try await Self.withTenant("e2e-log") { tenant in
            let season = try Season(
                id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"),
                federationSeasonID: "21", createdAt: Date(), updatedAt: Date())
            let competition = try Competition(
                id: CompetitionID(raw: UUID()), seasonID: season.id,
                modality: .futbol11, gender: .masculino,
                federationCompetitionID: "24037548", federationGroupID: "24037549",
                ageCategory: .cadete, divisionLabel: "Primera División Autonómica",
                groupLabel: "Grupo 1", createdAt: Date(), updatedAt: Date())
            try await tenant.scope {
                try await $0.seasons.save(season)
                try await $0.competitions.save(competition)
            }

            let useCase = IngestCalendar(
                unitOfWork: FluentTenantUnitOfWork(controlDatabase: tenant.app.db(.control)),
                federation: StubFederationClient(returning: Self.brokenCalendar()),
                clock: FixedInstantClock(instant: Self.syncInstant),
                ids: SystemUUIDProvider())

            await #expect(throws: DomainError.self) {
                try await useCase.execute(
                    competitionID: competition.id,
                    actor: .init(clubSlug: try Slug("e2e-log"), isSystem: true))
            }

            let after = try await tenant.scope { repositories in
                (teams: try await repositories.teams.list(),
                 runs: try await repositories.ingestionRuns.list(
                    competitionID: competition.id, limit: 10))
            }

            // Lo de la pasada, deshecho.
            #expect(after.teams.isEmpty)
            // El registro, no.
            #expect(after.runs.count == 1)
            #expect(after.runs.first?.outcome == .failed)
            #expect(after.runs.first?.error?.isEmpty == false)
            #expect(after.runs.first?.matchesCreated == 0)
        }
    }

    /// Ida y vuelta del registro con **descartes dentro**, que es donde vive el
    /// `jsonb`.
    ///
    /// Se prueba aquí y no en el nivel 2 por lo mismo que lo anterior: la forma
    /// del documento es cosa del driver, y Postgres ya cazó una vez que un array
    /// de Swift se enlaza como `jsonb[]` y no como `jsonb`.
    @Test("el registro guarda y recupera sus descartes (D-85, §4.4)")
    func theRunRecordRoundTripsItsSkips() async throws {
        try await Self.withTenant("e2e-skips") { tenant in
            let season = try Season(
                id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"),
                federationSeasonID: "21", createdAt: Date(), updatedAt: Date())
            let competition = try Competition(
                id: CompetitionID(raw: UUID()), seasonID: season.id,
                modality: .futbol11, gender: .masculino,
                federationCompetitionID: "24037548", federationGroupID: "24037549",
                ageCategory: .cadete, divisionLabel: "Primera División Autonómica",
                groupLabel: "Grupo 1", createdAt: Date(), updatedAt: Date())
            try await tenant.scope {
                try await $0.seasons.save(season)
                try await $0.competitions.save(competition)
            }

            let useCase = IngestCalendar(
                unitOfWork: FluentTenantUnitOfWork(controlDatabase: tenant.app.db(.control)),
                federation: StubFederationClient(returning: Self.calendarWithADatelessMatch()),
                clock: FixedInstantClock(instant: Self.syncInstant),
                ids: SystemUUIDProvider())

            _ = try await useCase.execute(
                competitionID: competition.id,
                actor: .init(clubSlug: try Slug("e2e-skips"), isSystem: true))

            let runs = try await tenant.scope {
                try await $0.ingestionRuns.list(competitionID: competition.id, limit: 10)
            }

            #expect(runs.count == 1)
            #expect(runs.first?.outcome == .succeeded)
            #expect(runs.first?.matchesCreated == 1)
            #expect(runs.first?.skipped == [IngestionSkip(
                reason: .missingMatchDate,
                detail: "[2] E.F.M.O. BOADILLA - LAS ROZAS C.F.")])
        }
    }

    /// Una jornada con un partido bueno y otro **sin fecha**, que la pasada deja
    /// fuera y reporta (`D-75`).
    static func calendarWithADatelessMatch() -> FederationCalendar {
        func ref(_ id: String, _ name: String) -> FederationTeamRef {
            FederationTeamRef(
                federationTeamID: id, name: name, letter: "A",
                federationClubID: "club-\(id)", crestURL: nil)
        }
        func match(
            _ acta: String, _ home: FederationTeamRef, _ away: FederationTeamRef, _ date: Date?
        ) -> FederationMatch {
            FederationMatch(
                federationMatchID: acta, home: home, away: away,
                homeScore: nil, awayScore: nil, date: date, kickoff: nil,
                venue: nil, venueCode: nil)
        }
        return FederationCalendar(
            seasonLabel: try! SeasonLabel("2025/26"),
            competitionName: nil, groupLabel: "Grupo 1", currentRound: 1,
            rounds: [FederationRound(number: 1, label: "1", matches: [
                match("1", ref("821", "CELTIC CASTILLA C.F."),
                      ref("304468", "C.D. GALAPAGAR"),
                      Date(timeIntervalSince1970: 1_758_931_200)),
                match("2", ref("900", "E.F.M.O. BOADILLA"),
                      ref("901", "LAS ROZAS C.F."), nil),
            ])])
    }

    /// Una jornada con dos partidos: el primero es bueno y el segundo enfrenta a
    /// un equipo consigo mismo, que `Match` rechaza (§3.5).
    static func brokenCalendar() -> FederationCalendar {
        func ref(_ id: String, _ name: String) -> FederationTeamRef {
            FederationTeamRef(
                federationTeamID: id, name: name, letter: "A",
                federationClubID: "club-\(id)", crestURL: nil)
        }
        let date = Date(timeIntervalSince1970: 1_758_931_200)
        func match(_ acta: String, _ home: FederationTeamRef, _ away: FederationTeamRef)
            -> FederationMatch
        {
            FederationMatch(
                federationMatchID: acta, home: home, away: away,
                homeScore: nil, awayScore: nil, date: date, kickoff: nil,
                venue: nil, venueCode: nil)
        }
        let celtic = ref("821", "CELTIC CASTILLA C.F.")
        let galapagar = ref("304468", "C.D. GALAPAGAR")
        let boadilla = ref("900", "E.F.M.O. BOADILLA")

        return FederationCalendar(
            seasonLabel: try! SeasonLabel("2025/26"),
            competitionName: nil, groupLabel: "Grupo 1", currentRound: 1,
            rounds: [FederationRound(number: 1, label: "1", matches: [
                match("1", celtic, galapagar),
                match("2", boadilla, boadilla),
            ])])
    }
}

/// Devuelve el calendario que se le dé, sin tocar el parser. Para el caso de
/// rollback hace falta un calendario **imposible**, y ningún volcado real lo es.
struct StubFederationClient: FederationClient {
    let calendar: FederationCalendar
    init(returning calendar: FederationCalendar) { self.calendar = calendar }
    func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar {
        calendar
    }
}

/// El reloj fijo del nivel 3. Los dobles del nivel 2 viven en `ApplicationTests`
/// y ese *target* no lo ve éste.
struct FixedInstantClock: Clock {
    let instant: Date
    func now() -> Date { instant }
}
