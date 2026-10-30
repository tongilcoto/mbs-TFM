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

/// Nivel 4 (§8.1): `GET /v1/standings?roundId=` (`D-34`, R4.7). La racha y la
/// resolución de los nombres las prueban los niveles 1 y 2; aquí se prueba **el
/// borde**: la ruta, cada campo de la fila, el `TeamRef` de un propio y de un
/// rival, la racha como `victoria`/`derrota`, la tabla vacía, el 404 y los 400.
@Suite("Standings · D-34 · la clasificación de una jornada",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct StandingEndpointTests {

    static let prefix = "e2e_"
    static let slug = "standclub"
    static let createdAt = Date(timeIntervalSince1970: 1_760_000_000)

    struct Seeded: Sendable {
        let rounds: [RoundID]
        let competition: CompetitionID
        let own: TeamID, rival: TeamID
        let clubName: String, clubShortName: String
    }

    static func day(_ text: String) -> Date { try! Date("\(text)T00:00:00Z", strategy: .iso8601) }

    /// El Cadete A propio contra el «C.D. GALAPAGAR» B: la jornada 1 la gana el
    /// propio (2-0), la 2 el rival (3-1), la 3 sin jugar. Tabla de la 1 y de la 2.
    static func withSeededClub(
        _ body: @escaping @Sendable (Application, Seeded) async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(slug, federation: .rffm, schemaPrefix: prefix, on: app)

            let competition = CompetitionID(raw: UUID())
            let rounds = (1...3).map { _ in RoundID(raw: UUID()) }
            let (own, rival) = (TeamID(raw: UUID()), TeamID(raw: UUID()))
            let unitOfWork = FluentTenantUnitOfWork(controlDatabase: app.db(.control))
            let club = try await unitOfWork.withRepositories(actor: ActorContext(clubSlug: try Slug(slug))) {
                repositories -> Domain.Club in
                let season = try Season(
                    id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"), federationSeasonID: "21",
                    createdAt: createdAt, updatedAt: createdAt)
                try await repositories.seasons.save(season)
                try await repositories.competitions.save(try Competition(
                    id: competition, seasonID: season.id, modality: .futbol11, gender: .masculino,
                    federationCompetitionID: "24037548", federationGroupID: "24037549", ageCategory: .cadete,
                    divisionLabel: "PRIMERA CADETE", groupLabel: "Grupo 1", createdAt: createdAt, updatedAt: createdAt))
                for (index, id) in rounds.enumerated() {
                    let date = day("2025-10-0\(4 + index)")
                    try await repositories.rounds.save(try Round(
                        id: id, competitionID: competition, number: index + 1, startDate: date, endDate: date,
                        createdAt: createdAt, updatedAt: createdAt))
                }
                let rivalClub = try OpponentClub(
                    id: OpponentClubID(raw: UUID()), name: "C.D. GALAPAGAR", shortName: "Galapagar",
                    slug: try Slug("c-d-galapagar"), createdAt: createdAt, updatedAt: createdAt)
                try await repositories.opponentClubs.save(rivalClub)
                try await repositories.teams.save(try Team(
                    id: own, category: .cadete, letter: "A", gender: .masculino, modality: .futbol11,
                    createdAt: createdAt, updatedAt: createdAt))
                try await repositories.teams.save(try Team(
                    id: rival, opponentClubID: rivalClub.id, seasonID: season.id, category: .cadete, letter: "B",
                    gender: .masculino, modality: .futbol11, createdAt: createdAt, updatedAt: createdAt))
                for (round, home, away, score) in [(0, own, rival, (2, 0)), (1, rival, own, (3, 1))] {
                    try await repositories.matches.save(try Match(
                        id: MatchID(raw: UUID()), competitionID: competition, roundID: rounds[round],
                        kickoff: Kickoff(date: day("2025-10-0\(4 + round)")), homeTeamID: home, awayTeamID: away,
                        result: try MatchResult(homeScore: score.0, awayScore: score.1), status: .finalizado,
                        createdAt: createdAt, updatedAt: createdAt))
                }
                for (round, team, position, previous, won, lost, goalsFor, goalsAgainst, points) in [
                    (0, own, 1, nil, 1, 0, 2, 0, 3), (0, rival, 2, nil, 0, 1, 0, 2, 0),
                    (1, rival, 1, 2, 1, 1, 3, 3, 3), (1, own, 2, 1, 1, 1, 3, 3, 3),
                ] as [(Int, TeamID, Int, Int?, Int, Int, Int, Int, Int)] {
                    try await repositories.standingRows.save(try StandingRow(
                        id: StandingRowID(raw: UUID()), competitionID: competition, roundID: rounds[round],
                        teamID: team, position: position, previousPosition: previous, played: round + 1, won: won,
                        drawn: 0, lost: lost, goalsFor: goalsFor, goalsAgainst: goalsAgainst, points: points,
                        createdAt: createdAt, updatedAt: createdAt))
                }
                return try #require(try await repositories.clubs.current())
            }

            try await body(app, Seeded(
                rounds: rounds, competition: competition, own: own, rival: rival,
                clubName: club.name, clubShortName: club.shortName))
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    static func decode(_ response: TestingHTTPResponse) throws -> [Components.Schemas.StandingResponse] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Components.Schemas.StandingResponse].self, from: Data(response.body.readableBytesView))
    }

    static func problem(_ response: TestingHTTPResponse) throws -> Components.Schemas.Problem {
        try JSONDecoder().decode(Components.Schemas.Problem.self, from: Data(response.body.readableBytesView))
    }

    static func header(_ request: inout TestingHTTPRequest) {
        request.headers.add(name: "X-Club", value: slug)
    }

    @Test("la tabla de la jornada, por puesto, con cada campo de la fila")
    func theTableFieldByField() async throws {
        try await Self.withSeededClub { app, seeded in
            try await app.testing().test(
                .GET, "/v1/standings?roundId=\(seeded.rounds[1])", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                #expect(response.status == .ok)
                let rows = try Self.decode(response)
                #expect(rows.map(\.team.value1.teamId) == ["\(seeded.rival)", "\(seeded.own)"])
                let row = try #require(rows.last)
                #expect(row.competitionId == "\(seeded.competition)")
                #expect(row.roundId == "\(seeded.rounds[1])")
                #expect(row.position == 2)
                #expect(row.previousPosition == 1)
                #expect(row.played == 2)
                #expect(row.won == 1)
                #expect(row.drawn == 0)
                #expect(row.lost == 1)
                #expect(row.goalsFor == 3)
                #expect(row.goalsAgainst == 3)
                #expect(row.points == 3)
                #expect(!row.id.isEmpty)
            }
        }
    }

    /// El `TeamRef` de cada fila, con los nombres de **su** club (`D-32`, `D-111`).
    @Test("el equipo de cada fila: el propio con su club y el rival con el suyo")
    func theTeamOfEachRow() async throws {
        try await Self.withSeededClub { app, seeded in
            try await app.testing().test(
                .GET, "/v1/standings?roundId=\(seeded.rounds[1])", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                let rows = try Self.decode(response)
                let rival = try #require(rows.first).team.value1
                #expect(rival.displayName == "Galapagar Cadete B")
                #expect(rival.shortDisplayName == "Galapagar B")
                #expect(rival.nameWithLetter == "C.D. GALAPAGAR B")
                #expect(rival.isOwn == false)
                #expect(rival.crestUrl == nil)
                let own = try #require(rows.last).team.value1
                #expect(own.nameWithLetter == "\(seeded.clubName) A")
                #expect(own.shortDisplayName == "\(seeded.clubShortName) A")
                #expect(own.isOwn)
            }
        }
    }

    @Test("la racha de cada fila, del más reciente al más antiguo y hasta esa jornada")
    func theFormOfEachRow() async throws {
        try await Self.withSeededClub { app, seeded in
            try await app.testing().test(
                .GET, "/v1/standings?roundId=\(seeded.rounds[1])", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                let rows = try Self.decode(response)
                let form = rows.map { $0.form.map { "\($0.roundNumber):\($0.outcome.value1.rawValue)" } }
                #expect(form == [["2:victoria", "1:derrota"], ["2:derrota", "1:victoria"]])
            }
            try await app.testing().test(
                .GET, "/v1/standings?roundId=\(seeded.rounds[0])", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                let rows = try Self.decode(response)
                #expect(rows.map { $0.form.count } == [1, 1])
                #expect(rows.allSatisfy { $0.previousPosition == nil })
                // Tras la jornada 1, ganados y perdidos, y goles a favor y en contra, son
                // distintos en cada fila: así se ve si alguno se cruza (la mutación lo pilló).
                #expect(rows.map(\.won) == [1, 0])
                #expect(rows.map(\.lost) == [0, 1])
                #expect(rows.map(\.goalsFor) == [2, 0])
                #expect(rows.map(\.goalsAgainst) == [0, 2])
            }
        }
    }

    @Test("una jornada sin tabla todavía da la lista vacía")
    func aRoundWithoutTable() async throws {
        try await Self.withSeededClub { app, seeded in
            try await app.testing().test(
                .GET, "/v1/standings?roundId=\(seeded.rounds[2])", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                #expect(response.status == .ok)
                #expect(try Self.decode(response).isEmpty)
            }
        }
    }

    @Test("una jornada que no existe es 404 ROUND_NOT_FOUND")
    func anUnknownRoundIs404() async throws {
        try await Self.withSeededClub { app, _ in
            try await app.testing().test(
                .GET, "/v1/standings?roundId=\(UUID())", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                #expect(response.status == .notFound)
                #expect(try Self.problem(response).code == .ROUND_NOT_FOUND)
            }
        }
    }

    @Test("sin roundId es 400 BAD_REQUEST, y uno que no es un UUID, 400 INVALID_UUID",
          arguments: [("/v1/standings", "BAD_REQUEST"), ("/v1/standings?roundId=abc", "INVALID_UUID")])
    func badQueriesAre400(path: String, code: String) async throws {
        try await Self.withSeededClub { app, _ in
            try await app.testing().test(.GET, path, beforeRequest: { Self.header(&$0) }) { response async throws in
                #expect(response.status == .badRequest)
                #expect(try Self.problem(response).code?.rawValue == code)
            }
        }
    }
}
