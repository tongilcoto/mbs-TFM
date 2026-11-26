import Domain
import Foundation
import Testing

@testable import Application

/// Nivel 2 (§8.1): **la pasada de actas** (R7.12, D-138), con los puertos falseados, sin I/O y con reloj e ids
/// fijos. Esta primera parte: **qué partidos pregunta** (D-133, punto 1) y **qué pasa con cada acta** —sin cerrar,
/// que no se pudo leer o que no es de ese partido— antes de escribir nada (D-133, punto 2; D-138, puntos 1 y 7).
@Suite("IngestMatchReports · D-138 · qué actas pide la pasada y cuáles se cargan")
struct IngestMatchReportsTests {

    /// 2026-11-25, 20:00 en Madrid (19:00 UTC).
    static let now = Date(timeIntervalSince1970: 1_795_633_200)

    // ── Andamiaje ────────────────────────────────────────────────────────────

    /// La federación de mentira: el acta que se le prepare para cada código, o el fallo; y qué códigos le pidieron.
    final class ReportClient: FederationClient, @unchecked Sendable {
        var reports: [String: Result<FederationMatchReport, any Error>] = [:]
        private(set) var asked: [String] = []
        /// La ficha de cada equipo, por su código (`D-127`, punto 1), y qué fichas le pidieron.
        var rosters: [String: FederationTeamRoster] = [:]
        private(set) var askedRosters: [String] = []

        func fetchTeamRoster(federationTeamID: String) async throws -> FederationTeamRoster {
            askedRosters.append(federationTeamID)
            guard let roster = rosters[federationTeamID] else {
                throw FederationError.coordinateNotFound(detail: "sin ficha: \(federationTeamID)")
            }
            return roster
        }

        func fetchMatchReport(federationMatchID: String) async throws -> FederationMatchReport {
            asked.append(federationMatchID)
            guard let result = reports[federationMatchID] else {
                throw FederationError.coordinateNotFound(detail: "sin preparar: \(federationMatchID)")
            }
            return try result.get()
        }
        func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar {
            throw NotStubbed(client: "ReportClient", operation: "fetchCalendar")
        }
        func fetchStandings(_ coordinate: FederationCoordinate, round: Int) async throws -> FederationStanding {
            throw NotStubbed(client: "ReportClient", operation: "fetchStandings")
        }
        func fetchScorers(_ coordinate: FederationCoordinate) async throws -> FederationScorerTable {
            throw NotStubbed(client: "ReportClient", operation: "fetchScorers")
        }
        func coordinate(fromCalendarURL url: String) throws -> FederationCoordinate {
            throw NotStubbed(client: "ReportClient", operation: "coordinate(fromCalendarURL:)")
        }
    }

    struct Fixture: Sendable {
        let store: IngestionStore
        let competition: CompetitionID
        let round: RoundID
        let season: Season
        /// El Cadete A del club, «821» en la competición; el B, «822».
        let cadeteA: Team
        let cadeteB: Team
        /// Un rival, «900».
        let rival: Team
    }

    static func day(_ text: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = text.split(separator: "-").map { Int($0)! }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }

    static func seed(archived: Bool = false, label: String = "2026/27") async throws -> Fixture {
        let store = IngestionStore()
        let season = try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel(label), federationSeasonID: "22",
            archivedAt: archived ? now : nil, createdAt: now, updatedAt: now)
        let competition = try Competition(
            id: CompetitionID(raw: UUID()), seasonID: season.id, modality: .futbol11, gender: .masculino,
            federationCompetitionID: "24037548", federationGroupID: "24037549", ageCategory: .cadete,
            divisionLabel: "Primera División Autonómica", groupLabel: "Grupo 1", createdAt: now, updatedAt: now)
        let round = try Round(
            id: RoundID(raw: UUID()), competitionID: competition.id, number: 10,
            startDate: day("2026-11-21"), endDate: day("2026-11-22"), createdAt: now, updatedAt: now)
        func own(_ letter: String) throws -> Team {
            try Team(id: TeamID(raw: UUID()), category: .cadete, letter: letter, gender: .masculino,
                     modality: .futbol11, createdAt: now, updatedAt: now)
        }
        let (a, b) = (try own("A"), try own("B"))
        let rivalClub = try OpponentClub(
            id: OpponentClubID(raw: UUID()), name: "C.D. Rival", shortName: "Rival", slug: try Slug("cd-rival"),
            federationClubID: "999", createdAt: now, updatedAt: now)
        let rival = try Team(
            id: TeamID(raw: UUID()), opponentClubID: rivalClub.id, seasonID: season.id, category: .cadete,
            letter: "A", gender: .masculino, modality: .futbol11, federationTeamID: "900",
            createdAt: now, updatedAt: now)
        await store.seed(club: try Club(
            id: ClubID(raw: UUID()), name: "Celtic Castilla", shortName: "Celtic", slug: try Slug("celtic"),
            federation: .rffm, createdAt: now, updatedAt: now))
        await store.seed(seasons: [season], competitions: [competition], rounds: [round],
                         opponentClubs: [rivalClub], teams: [a, b, rival])
        await store.seed(teamRegistrations: [
            try TeamRegistration(id: TeamRegistrationID(raw: UUID()), team: a, seasonID: season.id,
                                 competitionID: competition.id, federationTeamID: "821", createdAt: now, updatedAt: now),
            try TeamRegistration(id: TeamRegistrationID(raw: UUID()), team: b, seasonID: season.id,
                                 competitionID: competition.id, federationTeamID: "822", createdAt: now, updatedAt: now),
        ])
        return Fixture(store: store, competition: competition.id, round: round.id, season: season,
                       cadeteA: a, cadeteB: b, rival: rival)
    }

    /// Un partido de la competición. Por defecto, el Cadete A en casa contra el rival, el sábado a las 11:00.
    @discardableResult
    static func match(
        _ f: Fixture, code: String?, home: Team? = nil, away: Team? = nil,
        date: String = "2026-11-21", time: WallClockTime? = WallClockTime(hour: 11, minute: 0),
        restDay: Bool = false
    ) async throws -> Match {
        let match = try Match(
            id: MatchID(raw: UUID()), competitionID: f.competition, roundID: f.round,
            kickoff: Kickoff(date: day(date), time: time), homeTeamID: (home ?? f.cadeteA).id,
            awayTeamID: (away ?? f.rival).id, status: .programado, federationMatchID: code, isRestDay: restDay,
            createdAt: now, updatedAt: now)
        await f.store.save(match)
        return match
    }

    /// Un acta, cerrada o no, con los dos códigos de equipo y nada más.
    static func report(closed: Bool = true, home: String = "821", away: String = "900") -> FederationMatchReport {
        FederationMatchReport(
            isClosed: closed, homeTeamFederationID: home, awayTeamFederationID: away,
            homeScore: closed ? 1 : nil, awayScore: closed ? 0 : nil, players: [], goals: [], cards: [], skipped: [])
    }

    /// El diccionario de nombres de estas pruebas (`D-123`).
    static let names = CastilianNames(text: "GARCÍA\nLÓPEZ\nMUÑOZ\nPÉREZ")

    static func useCase(_ f: Fixture, _ client: ReportClient) -> IngestMatchReports {
        IngestMatchReports(
            unitOfWork: FakeUnitOfWork(store: f.store), federation: client,
            clock: FixedClock(instant: now), ids: SequentialUUIDProvider(), names: FixedNameDictionary(names))
    }

    static let actor = ActorContext(clubSlug: try! Slug("celtic"), isSystem: true)

    static func classify(_ f: Fixture, _ client: ReportClient) async throws -> IngestMatchReports.Classified {
        let useCase = Self.useCase(f, client)
        let plan = try #require(try await useCase.plan(competitionID: f.competition, actor: actor))
        return await useCase.classify(plan)
    }

    // ── Qué partidos pregunta (D-133, punto 1) ───────────────────────────────

    @Test("pregunta por los del club que ya han empezado, con código de acta y sin el acta cargada")
    func asksOnlyForTheDueOnes() async throws {
        let f = try await Self.seed()
        try await Self.match(f, code: "1")                                        // sí: del club, el sábado
        try await Self.match(f, code: "2", home: f.rival, away: f.cadeteB)        // sí: del club, fuera
        try await Self.match(f, code: "3", date: "2026-11-28")                    // no: la semana que viene
        try await Self.match(f, code: nil)                                        // no: sin código de acta
        try await Self.match(f, code: "5", restDay: true)                         // no: descanso
        let loaded = try await Self.match(f, code: "6")                           // no: ya cargada
        await f.store.seed(reportCopy: MatchReportCopy(loadedAt: Self.now, lineup: []), for: loaded.id)
        let client = ReportClient()

        _ = try await Self.classify(f, client)

        #expect(client.asked.sorted() == ["1", "2"])
    }

    /// Entre dos rivales no hay acta que cargar (`D-130`): la competición los tiene, pero no son del club.
    @Test("no pregunta por los partidos entre dos rivales")
    func skipsRivalsOnly() async throws {
        let f = try await Self.seed()
        let other = try Team(
            id: TeamID(raw: UUID()), opponentClubID: f.rival.opponentClubID, seasonID: f.season.id,
            category: .cadete, letter: "B", gender: .masculino, modality: .futbol11, federationTeamID: "901",
            createdAt: Self.now, updatedAt: Self.now)
        await f.store.save(other)
        try await Self.match(f, code: "1", home: f.rival, away: other)
        let client = ReportClient()

        _ = try await Self.classify(f, client)

        #expect(client.asked.isEmpty)
    }

    /// Sin hora, cuenta el final del día de Madrid (`D-133`, punto 1): el de hoy sin hora, todavía no.
    @Test("sin hora, desde el final del día: el de ayer sí, el de hoy todavía no")
    func withoutTimeWaitsForTheEndOfTheDay() async throws {
        let f = try await Self.seed()
        try await Self.match(f, code: "ayer", date: "2026-11-24", time: nil)
        try await Self.match(f, code: "hoy", date: "2026-11-25", time: nil)
        try await Self.match(f, code: "hoy-tarde", date: "2026-11-25", time: WallClockTime(hour: 21, minute: 0))
        let client = ReportClient()

        _ = try await Self.classify(f, client)

        #expect(client.asked == ["ayer"])
    }

    /// `D-138`, punto 2: la archivada, nunca. Ni se pregunta ni deja fila.
    @Test("en una temporada archivada no hay pasada de actas")
    func archivedSeasonHasNoPass() async throws {
        let f = try await Self.seed(archived: true)
        try await Self.match(f, code: "1")

        let plan = try await Self.useCase(f, ReportClient()).plan(competitionID: f.competition, actor: Self.actor)

        #expect(plan == nil)
    }

    // ── Qué pasa con cada acta (D-133, punto 2; D-138, puntos 1 y 7) ─────────

    @Test("el acta cerrada y de ese partido se carga; la que no está cerrada, todavía no")
    func closedIsLoadedOpenIsNot() async throws {
        let f = try await Self.seed()
        let cerrado = try await Self.match(f, code: "1")
        try await Self.match(f, code: "2")
        let client = ReportClient()
        client.reports = ["1": .success(Self.report()), "2": .success(Self.report(closed: false))]

        let classified = try await Self.classify(f, client)

        #expect(classified.toLoad.map(\.match.id) == [cerrado.id])
        #expect(classified.notClosed == 1)
        #expect(classified.failed.isEmpty)
    }

    /// `D-138`, punto 1: un acta que falla no hunde la pasada. Se cuenta, con su código, y las demás siguen.
    @Test("la que la federación no da se cuenta como fallida, con su código, y las demás siguen")
    func failedIsCountedAndTheRestGoOn() async throws {
        let f = try await Self.seed()
        try await Self.match(f, code: "1")
        try await Self.match(f, code: "2")
        let client = ReportClient()
        client.reports = [
            "1": .failure(FederationError.transportFailure(url: "https://www.rffm.es/acta-partido/1", reason: "caída")),
            "2": .success(Self.report()),
        ]

        let classified = try await Self.classify(f, client)

        #expect(classified.toLoad.map(\.match.federationMatchID) == ["2"])
        #expect(classified.failed.map(\.reason) == [.unreadableMatchReport])
        #expect(classified.failed.first?.detail.hasPrefix("1: ") == true, "\(classified.failed)")
    }

    /// `D-138`, punto 7: el acta tiene que ser de ese partido. Si sus equipos no son los nuestros, no se carga.
    @Test("un acta con otros equipos que los del partido no se carga: fallida",
          arguments: [("821", "901"), ("900", "821"), ("822", "900")])
    func otherTeamsFail(_ codes: (String, String)) async throws {
        let f = try await Self.seed()
        try await Self.match(f, code: "1")
        let client = ReportClient()
        client.reports = ["1": .success(Self.report(home: codes.0, away: codes.1))]

        let classified = try await Self.classify(f, client)

        #expect(classified.toLoad.isEmpty)
        #expect(classified.failed.map(\.reason) == [.unreadableMatchReport])
    }

    /// La comprobación vale también con el club fuera, y entre dos equipos del club.
    @Test("los equipos se comprueban con el club fuera y entre dos equipos del club")
    func checksBothSides() async throws {
        let f = try await Self.seed()
        try await Self.match(f, code: "1", home: f.rival, away: f.cadeteA)
        try await Self.match(f, code: "2", home: f.cadeteA, away: f.cadeteB)
        let client = ReportClient()
        client.reports = ["1": .success(Self.report(home: "900", away: "821")),
                          "2": .success(Self.report(home: "821", away: "822"))]

        let classified = try await Self.classify(f, client)

        #expect(classified.toLoad.count == 2)
        #expect(classified.failed.isEmpty)
    }

    /// Un acta sin cerrar no se mira por sus equipos: la de antes del partido viene sin nadie, pero los equipos sí
    /// (R7.11). Lo que importa es que no se carga y se vuelve a pedir.
    @Test("un acta sin cerrar cuenta como sin cerrar, no como fallida")
    func openIsNotFailed() async throws {
        let f = try await Self.seed()
        try await Self.match(f, code: "1")
        let client = ReportClient()
        client.reports = ["1": .success(Self.report(closed: false, home: "", away: ""))]

        let classified = try await Self.classify(f, client)

        #expect(classified.notClosed == 1 && classified.failed.isEmpty && classified.toLoad.isEmpty)
    }
}
