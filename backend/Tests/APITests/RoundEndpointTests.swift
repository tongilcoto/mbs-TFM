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

/// Nivel 4 (§8.1): `GET /v1/rounds?competitionId=` y `GET /v1/rounds/{roundId}`
/// (R4.6). El orden y la regla de «en curso» los prueban los niveles 1 y 2; aquí
/// se prueba **el borde**: la ruta, cada campo, las fechas como días, los 404 y
/// los 400. Con el reloj fijo, para que «en curso» no dependa del día.
@Suite("Rounds · R4.6 · las jornadas de una competición",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct RoundEndpointTests {

    static let prefix = "e2e_"
    static let slug = "roundsclub"
    static let createdAt = Date(timeIntervalSince1970: 1_760_000_000)
    /// Miércoles 8 de octubre de 2025: entre la jornada 1 y la 2.
    static let today = try! Date("2025-10-08T12:00:00Z", strategy: .iso8601)

    struct FixedClock: Clock {
        let instant: Date
        func now() -> Date { instant }
    }

    struct Seeded: Sendable {
        let competition: CompetitionID
        let first: RoundID, second: RoundID, third: RoundID
        let otherCompetitionRound: RoundID
    }

    static func day(_ text: String) -> Date { try! Date("\(text)T00:00:00Z", strategy: .iso8601) }

    /// Tres jornadas de fin de semana, **guardadas desordenadas**, y una de otra
    /// competición.
    static func withSeededClub(
        _ body: @escaping @Sendable (Application, Seeded) async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp(clock: FixedClock(instant: today)) { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(slug, federation: .rffm, schemaPrefix: prefix, on: app)

            let seeded = Seeded(
                competition: CompetitionID(raw: UUID()), first: RoundID(raw: UUID()),
                second: RoundID(raw: UUID()), third: RoundID(raw: UUID()),
                otherCompetitionRound: RoundID(raw: UUID()))
            let other = CompetitionID(raw: UUID())
            let unitOfWork = FluentTenantUnitOfWork(controlDatabase: app.db(.control))
            try await unitOfWork.withRepositories(actor: ActorContext(clubSlug: try Slug(slug))) { repositories in
                let season = try Season(
                    id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"), federationSeasonID: "21",
                    createdAt: createdAt, updatedAt: createdAt)
                try await repositories.seasons.save(season)
                for (id, group) in [(seeded.competition, "24037549"), (other, "24037550")] {
                    try await repositories.competitions.save(try Competition(
                        id: id, seasonID: season.id, modality: .futbol11, gender: .masculino,
                        federationCompetitionID: "24037548", federationGroupID: group, ageCategory: .cadete,
                        divisionLabel: "PRIMERA CADETE", groupLabel: "Grupo 1",
                        createdAt: createdAt, updatedAt: createdAt))
                }
                for (id, competition, number, start, end) in [
                    (seeded.third, seeded.competition, 3, "2025-10-18", "2025-10-19"),
                    (seeded.otherCompetitionRound, other, 1, "2025-10-04", "2025-10-05"),
                    (seeded.first, seeded.competition, 1, "2025-10-04", "2025-10-05"),
                    (seeded.second, seeded.competition, 2, "2025-10-11", "2025-10-12"),
                ] {
                    try await repositories.rounds.save(try Round(
                        id: id, competitionID: competition, number: number, startDate: day(start),
                        endDate: day(end), createdAt: createdAt, updatedAt: createdAt))
                }
            }

            try await body(app, seeded)
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, _ response: TestingHTTPResponse) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(response.body.readableBytesView))
    }

    static func problem(_ response: TestingHTTPResponse) throws -> Components.Schemas.Problem {
        try JSONDecoder().decode(Components.Schemas.Problem.self, from: Data(response.body.readableBytesView))
    }

    static func header(_ request: inout TestingHTTPRequest) {
        request.headers.add(name: "X-Club", value: slug)
    }

    // ── listRounds ──────────────────────────────────────────────────────────

    @Test("listRounds: las de la competición, por número, y solo la próxima en curso")
    func listsTheRounds() async throws {
        try await Self.withSeededClub { app, seeded in
            try await app.testing().test(
                .GET, "/v1/rounds?competitionId=\(seeded.competition)", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                #expect(response.status == .ok)
                let rounds = try Self.decode([Components.Schemas.RoundResponse].self, response)
                #expect(rounds.map(\.id) == ["\(seeded.first)", "\(seeded.second)", "\(seeded.third)"])
                #expect(rounds.map(\.number) == [1, 2, 3])
                #expect(rounds.map(\.isCurrent) == [false, true, false])
            }
        }
    }

    @Test("listRounds: cada campo de una jornada, con las fechas como días")
    func mapsEveryRoundField() async throws {
        try await Self.withSeededClub { app, seeded in
            try await app.testing().test(
                .GET, "/v1/rounds?competitionId=\(seeded.competition)", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                let round = try #require(try Self.decode([Components.Schemas.RoundResponse].self, response)
                    .first { $0.id == "\(seeded.second)" })
                #expect(round.competitionId == "\(seeded.competition)")
                #expect(round.number == 2)
                #expect(round.startDate == "2025-10-11")
                #expect(round.endDate == "2025-10-12")
                #expect(round.isCurrent)
            }
        }
    }

    @Test("listRounds: una competición que no existe es 404 COMPETITION_NOT_FOUND")
    func anUnknownCompetitionIs404() async throws {
        try await Self.withSeededClub { app, _ in
            try await app.testing().test(
                .GET, "/v1/rounds?competitionId=\(UUID())", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                #expect(response.status == .notFound)
                #expect(try Self.problem(response).code == .COMPETITION_NOT_FOUND)
            }
        }
    }

    @Test("listRounds: sin competitionId es 400 BAD_REQUEST, y uno que no es un UUID, 400 INVALID_UUID",
          arguments: [("/v1/rounds", "BAD_REQUEST"), ("/v1/rounds?competitionId=abc", "INVALID_UUID")])
    func badQueriesAre400(path: String, code: String) async throws {
        try await Self.withSeededClub { app, _ in
            try await app.testing().test(.GET, path, beforeRequest: { Self.header(&$0) }) { response async throws in
                #expect(response.status == .badRequest)
                #expect(try Self.problem(response).code?.rawValue == code)
            }
        }
    }

    // ── getRound ────────────────────────────────────────────────────────────

    @Test("getRound: la jornada en curso, con cada campo")
    func getsTheCurrentRound() async throws {
        try await Self.withSeededClub { app, seeded in
            try await app.testing().test(
                .GET, "/v1/rounds/\(seeded.second)", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                #expect(response.status == .ok)
                let round = try Self.decode(Components.Schemas.RoundResponse.self, response)
                #expect(round.id == "\(seeded.second)")
                #expect(round.competitionId == "\(seeded.competition)")
                #expect(round.number == 2)
                #expect(round.startDate == "2025-10-11")
                #expect(round.endDate == "2025-10-12")
                #expect(round.isCurrent)
            }
        }
    }

    /// La de la otra competición es su única jornada… y ya pasó (5 de octubre):
    /// ninguna de esa competición está en curso.
    @Test("getRound: una que no está en curso lo dice, también si su competición ya terminó")
    func roundsThatAreNotCurrent() async throws {
        try await Self.withSeededClub { app, seeded in
            for id in [seeded.third, seeded.otherCompetitionRound] {
                try await app.testing().test(
                    .GET, "/v1/rounds/\(id)", beforeRequest: { Self.header(&$0) }
                ) { response async throws in
                    #expect(response.status == .ok)
                    #expect(try Self.decode(Components.Schemas.RoundResponse.self, response).isCurrent == false)
                }
            }
        }
    }

    @Test("getRound: una jornada que no existe es 404 ROUND_NOT_FOUND")
    func anUnknownRoundIs404() async throws {
        try await Self.withSeededClub { app, _ in
            try await app.testing().test(
                .GET, "/v1/rounds/\(UUID())", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                #expect(response.status == .notFound)
                #expect(try Self.problem(response).code == .ROUND_NOT_FOUND)
            }
        }
    }

    @Test("getRound: un roundId que no es un UUID es 400 INVALID_UUID")
    func aRoundIdThatIsNotAUUIDIs400() async throws {
        try await Self.withSeededClub { app, _ in
            try await app.testing().test(
                .GET, "/v1/rounds/abc", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                #expect(response.status == .badRequest)
                #expect(try Self.problem(response).code == .INVALID_UUID)
            }
        }
    }
}
