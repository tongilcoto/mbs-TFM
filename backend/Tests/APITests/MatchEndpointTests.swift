import APIContract
import Application
import Domain
import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App
import TestSupport
@testable import Persistence
@testable import Tenancy

/// Nivel 4 (§8.1): `GET /v1/matches` (R4.8). Los ámbitos, el orden y la página
/// los prueba el nivel 2; aquí se prueba **el borde**: la ruta, el sobre de la
/// página, cada campo de un partido jugado y de uno sin jugar, cada lado con su
/// `TeamRef`, su marcador y su fila de la clasificación (`D-112`), y los 400 y 404.
@Suite("Matches · R4.8 · partidos, siempre dentro de un ámbito",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct MatchEndpointTests {

    static let prefix = "e2e_"
    static let slug = "matchclub"
    static let createdAt = Date(timeIntervalSince1970: 1_760_000_000)

    struct Seeded: Sendable {
        let season: SeasonID, competition: CompetitionID
        let rounds: [RoundID]
        let own: TeamID, rival: TeamID
        let played: MatchID, pending: MatchID
        let clubName: String
    }

    static func day(_ text: String) -> Date { try! Date("\(text)T00:00:00Z", strategy: .iso8601) }

    /// El Cadete A propio contra el «C.D. GALAPAGAR» B: la jornada 1, jugada
    /// (3-1, sábado a las 18:00, con su campo y su acta) y con tabla; la 2, sin
    /// jugar, sin hora y sin tabla.
    static func withSeededClub(
        _ body: @escaping @Sendable (Application, Seeded) async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(slug, federation: .rffm, schemaPrefix: prefix, on: app)

            let (season, competition) = (SeasonID(raw: UUID()), CompetitionID(raw: UUID()))
            let rounds = [RoundID(raw: UUID()), RoundID(raw: UUID())]
            let (own, rival) = (TeamID(raw: UUID()), TeamID(raw: UUID()))
            let (played, pending) = (MatchID(raw: UUID()), MatchID(raw: UUID()))
            let unitOfWork = FluentTenantUnitOfWork(controlDatabase: app.db(.control))
            let club = try await unitOfWork.withRepositories(actor: ActorContext(clubSlug: try Slug(slug))) {
                repositories -> Domain.Club in
                try await repositories.seasons.save(try Season(
                    id: season, label: try SeasonLabel("2025/26"), federationSeasonID: "21",
                    createdAt: createdAt, updatedAt: createdAt))
                try await repositories.competitions.save(try Competition(
                    id: competition, seasonID: season, modality: .futbol11, gender: .masculino,
                    federationCompetitionID: "24037548", federationGroupID: "24037549", ageCategory: .cadete,
                    divisionLabel: "PRIMERA CADETE", groupLabel: "Grupo 1", createdAt: createdAt, updatedAt: createdAt))
                for (index, (id, date)) in zip(rounds, ["2025-10-04", "2025-10-11"]).enumerated() {
                    try await repositories.rounds.save(try Round(
                        id: id, competitionID: competition, number: index + 1, startDate: day(date),
                        endDate: day(date), createdAt: createdAt, updatedAt: createdAt))
                }
                let rivalClub = try OpponentClub(
                    id: OpponentClubID(raw: UUID()), name: "C.D. GALAPAGAR", shortName: "Galapagar",
                    slug: try Slug("c-d-galapagar"), createdAt: createdAt, updatedAt: createdAt)
                try await repositories.opponentClubs.save(rivalClub)
                try await repositories.teams.save(try Team(
                    id: own, category: .cadete, letter: "A", gender: .masculino, modality: .futbol11,
                    createdAt: createdAt, updatedAt: createdAt))
                try await repositories.teams.save(try Team(
                    id: rival, opponentClubID: rivalClub.id, seasonID: season, category: .cadete, letter: "B",
                    gender: .masculino, modality: .futbol11, createdAt: createdAt, updatedAt: createdAt))
                try await repositories.matches.save(try Match(
                    id: played, competitionID: competition, roundID: rounds[0],
                    kickoff: Kickoff(date: day("2025-10-04"), time: WallClockTime(hour: 18, minute: 0)),
                    homeTeamID: own, awayTeamID: rival, result: try MatchResult(homeScore: 3, awayScore: 1),
                    status: .finalizado, venue: "CANAL ISABEL II", federationMatchID: "5348330",
                    createdAt: createdAt, updatedAt: createdAt))
                try await repositories.matches.save(try Match(
                    id: pending, competitionID: competition, roundID: rounds[1], kickoff: Kickoff(date: day("2025-10-11")),
                    homeTeamID: rival, awayTeamID: own, status: .programado, createdAt: createdAt, updatedAt: createdAt))
                // Cada número distinto de los demás: así se ve si se cruzan dos campos.
                for (team, position, won, drawn, lost, goalsFor, goalsAgainst, points) in [
                    (own, 1, 4, 2, 1, 15, 6, 14), (rival, 3, 3, 0, 4, 9, 12, 9),
                ] {
                    try await repositories.standingRows.save(try StandingRow(
                        id: StandingRowID(raw: UUID()), competitionID: competition, roundID: rounds[0], teamID: team,
                        position: position, played: won + drawn + lost, won: won, drawn: drawn, lost: lost,
                        goalsFor: goalsFor, goalsAgainst: goalsAgainst, points: points,
                        createdAt: createdAt, updatedAt: createdAt))
                }
                return try #require(try await repositories.clubs.current())
            }

            try await body(app, Seeded(
                season: season, competition: competition, rounds: rounds, own: own, rival: rival, played: played,
                pending: pending, clubName: club.name))
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    typealias PageBody = Operations.listMatches.Output.Ok.Body.jsonPayload

    static func decode(_ response: TestingHTTPResponse) throws -> PageBody {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PageBody.self, from: Data(response.body.readableBytesView))
    }

    static func problem(_ response: TestingHTTPResponse) throws -> Components.Schemas.Problem {
        try JSONDecoder().decode(Components.Schemas.Problem.self, from: Data(response.body.readableBytesView))
    }

    static func header(_ request: inout TestingHTTPRequest) {
        request.headers.add(name: "X-Club", value: slug)
    }

    // ── El sobre y el orden ─────────────────────────────────────────────────

    @Test("por equipo y temporada: los suyos en orden, con el sobre de la página")
    func byTeamAndSeason() async throws {
        try await Self.withSeededClub { app, seeded in
            try await app.testing().test(
                .GET, "/v1/matches?teamId=\(seeded.own)&seasonId=\(seeded.season)", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                #expect(response.status == .ok)
                let page = try Self.decode(response)
                #expect(page.value2.data.map(\.id) == ["\(seeded.played)", "\(seeded.pending)"])
                #expect(page.value1.page == 1)
                #expect(page.value1.perPage == 25)
                #expect(page.value1.total == 2)
            }
        }
    }

    @Test("order=desc y la página: del más reciente, de uno en uno")
    func newestFirstAndPaged() async throws {
        try await Self.withSeededClub { app, seeded in
            try await app.testing().test(
                .GET, "/v1/matches?competitionId=\(seeded.competition)&order=desc&perPage=1&page=2",
                beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                let page = try Self.decode(response)
                #expect(page.value2.data.map(\.id) == ["\(seeded.played)"])
                #expect((page.value1.page, page.value1.perPage, page.value1.total) == (2, 1, 2))
            }
        }
    }

    // ── Cada campo ──────────────────────────────────────────────────────────

    @Test("un partido jugado, campo a campo")
    func aPlayedMatchFieldByField() async throws {
        try await Self.withSeededClub { app, seeded in
            try await app.testing().test(
                .GET, "/v1/matches?roundId=\(seeded.rounds[0])", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                let match = try #require(try Self.decode(response).value2.data.first)
                #expect(match.id == "\(seeded.played)")
                #expect(match.competitionId == "\(seeded.competition)")
                #expect(match.roundId == "\(seeded.rounds[0])")
                #expect(match.roundNumber == 1)
                #expect(match.matchDate == "2025-10-04")
                #expect(match.kickoffTime == "18:00")
                #expect(match.isKickoffConfirmed)
                #expect(match.status.value1 == .finalizado)
                #expect(match.venue == "CANAL ISABEL II")
                #expect(match.federationMatchId == "5348330")
            }
        }
    }

    @Test("los dos lados de un partido jugado: el equipo, el marcador y su fila de esa jornada (D-112)")
    func theSidesOfAPlayedMatch() async throws {
        try await Self.withSeededClub { app, seeded in
            try await app.testing().test(
                .GET, "/v1/matches?roundId=\(seeded.rounds[0])", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                let match = try #require(try Self.decode(response).value2.data.first)
                let home = match.home.value1
                #expect(home.value1.teamId == "\(seeded.own)")
                #expect(home.value1.nameWithLetter == "\(seeded.clubName) A")
                #expect(home.value1.isOwn)
                #expect(home.value2.score == 3)
                let standing = try #require(home.value2.standing?.value1)
                #expect(standing.position == 1)
                #expect(standing.played == 7)
                #expect(standing.won == 4)
                #expect(standing.drawn == 2)
                #expect(standing.lost == 1)
                #expect(standing.goalsFor == 15)
                #expect(standing.goalsAgainst == 6)
                #expect(standing.points == 14)
                let away = match.away.value1
                #expect(away.value1.teamId == "\(seeded.rival)")
                #expect(away.value1.nameWithLetter == "C.D. GALAPAGAR B")
                #expect(away.value1.shortDisplayName == "Galapagar B")
                #expect(away.value1.isOwn == false)
                #expect(away.value2.score == 1)
                #expect(away.value2.standing?.value1?.position == 3)
            }
        }
    }

    @Test("un partido sin jugar: sin hora, programado, sin marcador y sin fila")
    func aPendingMatch() async throws {
        try await Self.withSeededClub { app, seeded in
            try await app.testing().test(
                .GET, "/v1/matches?roundId=\(seeded.rounds[1])", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                let match = try #require(try Self.decode(response).value2.data.first)
                #expect(match.id == "\(seeded.pending)")
                #expect(match.roundNumber == 2)
                #expect(match.kickoffTime == nil)
                #expect(match.isKickoffConfirmed == false)
                #expect(match.status.value1 == .programado)
                #expect(match.home.value1.value2.score == nil)
                #expect(match.home.value1.value2.standing?.value1 == nil)
                #expect(match.away.value1.value2.standing?.value1 == nil)
            }
        }
    }

    // ── Los 400 y los 404 ───────────────────────────────────────────────────

    @Test("sin ámbito es 400 MISSING_SCOPE, también con solo la temporada")
    func withoutScopeIs400() async throws {
        try await Self.withSeededClub { app, seeded in
            for path in ["/v1/matches", "/v1/matches?seasonId=\(seeded.season)"] {
                try await app.testing().test(.GET, path, beforeRequest: { Self.header(&$0) }) { response async throws in
                    #expect(response.status == .badRequest)
                    #expect(try Self.problem(response).code == .MISSING_SCOPE)
                }
            }
        }
    }

    @Test("una página o un tamaño fuera de rango, o un estado que no existe, es 400 BAD_REQUEST", arguments: [
        "perPage=0", "perPage=101", "page=0", "status=jugando",
    ])
    func outOfRangeIs400(query: String) async throws {
        try await Self.withSeededClub { app, seeded in
            try await app.testing().test(
                .GET, "/v1/matches?competitionId=\(seeded.competition)&\(query)", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                #expect(response.status == .badRequest)
                #expect(try Self.problem(response).code == .BAD_REQUEST)
            }
        }
    }

    @Test("un identificador que no es un UUID es 400 INVALID_UUID", arguments: [
        "roundId=abc", "competitionId=abc", "teamId=abc", "teamId=\(UUID())&seasonId=abc",
    ])
    func badIDsAre400(query: String) async throws {
        try await Self.withSeededClub { app, _ in
            try await app.testing().test(
                .GET, "/v1/matches?\(query)", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                #expect(response.status == .badRequest)
                #expect(try Self.problem(response).code == .INVALID_UUID)
            }
        }
    }

    @Test("un ámbito que no existe es su 404")
    func unknownScopesAre404() async throws {
        try await Self.withSeededClub { app, seeded in
            for (query, code) in [
                ("roundId=\(UUID())", "ROUND_NOT_FOUND"), ("competitionId=\(UUID())", "COMPETITION_NOT_FOUND"),
                ("teamId=\(UUID())", "TEAM_NOT_FOUND"), ("teamId=\(seeded.own)&seasonId=\(UUID())", "SEASON_NOT_FOUND"),
            ] {
                try await app.testing().test(
                    .GET, "/v1/matches?\(query)", beforeRequest: { Self.header(&$0) }
                ) { response async throws in
                    #expect(response.status == .notFound)
                    #expect(try Self.problem(response).code?.rawValue == code)
                }
            }
        }
    }
}
