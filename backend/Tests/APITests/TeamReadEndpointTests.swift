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

/// Nivel 4 (§8.1): `GET /v1/teams/{teamId}` (R3.7). El caso de uso está probado
/// en el nivel 2; aquí, **el borde**: cada campo de la respuesta, con los
/// derivados del club propio o del rival, y cada error con su código.
@Suite("Teams · §5.1 · un equipo, propio o rival (R3.7)",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct TeamReadEndpointTests {

    static let prefix = "e2e_"
    static let slug = "teamreadclub"
    static let now = Date(timeIntervalSince1970: 1_760_000_000)

    struct Seeded {
        let own: TeamID
        let rival: TeamID
        let rivalClub: OpponentClubID
        let season: SeasonID
    }

    /// Un equipo propio y un rival de una temporada, con su club.
    static func withSeededTeams(
        _ body: @escaping @Sendable (Application, Seeded) async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(slug, federation: .rffm, schemaPrefix: prefix, on: app)
            let seeded = Seeded(
                own: TeamID(raw: UUID()), rival: TeamID(raw: UUID()),
                rivalClub: OpponentClubID(raw: UUID()), season: SeasonID(raw: UUID()))
            try await FluentTenantUnitOfWork(controlDatabase: app.db(.control))
                .withRepositories(actor: ActorContext(clubSlug: try Slug(slug))) { repositories in
                    try await repositories.seasons.save(try Season(
                        id: seeded.season, label: try SeasonLabel("2026/27"),
                        federationSeasonID: "22", createdAt: now, updatedAt: now))
                    try await repositories.teams.save(try Team(
                        id: seeded.own, category: .alevin, letter: "A",
                        gender: .masculino, modality: .futbol7, createdAt: now, updatedAt: now))
                    try await repositories.opponentClubs.save(try OpponentClub(
                        id: seeded.rivalClub, name: "C.D. GALAPAGAR", shortName: "Galapagar",
                        slug: try Slug("c-d-galapagar"), createdAt: now, updatedAt: now))
                    try await repositories.teams.save(try Team(
                        id: seeded.rival, opponentClubID: seeded.rivalClub, seasonID: seeded.season,
                        category: .alevin, letter: "B", gender: .masculino, modality: .futbol7,
                        federationTeamID: "3349087", createdAt: now, updatedAt: now))
                }
            try await body(app, seeded)
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    static func get(
        _ app: Application, _ teamID: String,
        _ check: @escaping @Sendable (TestingHTTPResponse) async throws -> Void
    ) async throws {
        try await app.testing().test(
            .GET, "/v1/teams/\(teamID)",
            beforeRequest: { request in request.headers.add(name: "X-Club", value: slug) },
            afterResponse: check)
    }

    static func decodeTeam(_ response: TestingHTTPResponse) throws -> Components.Schemas.TeamResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            Components.Schemas.TeamResponse.self, from: Data(response.body.readableBytesView))
    }

    static func decodeProblem(_ response: TestingHTTPResponse) throws -> Components.Schemas.Problem {
        try JSONDecoder().decode(
            Components.Schemas.Problem.self, from: Data(response.body.readableBytesView))
    }

    static func lower(_ id: some CustomStringConvertible) -> String {
        "\(id)".lowercased()
    }

    @Test("un equipo propio: 200, cada campo, con el nombre del club propio")
    func readsAnOwnTeam() async throws {
        try await Self.withSeededTeams { app, seeded in
            try await Self.get(app, "\(seeded.own)") { response async throws in
                #expect(response.status == .ok)
                let team = try Self.decodeTeam(response)
                #expect(Self.lower(team.id) == Self.lower(seeded.own))
                #expect(team.category == .alevin)
                #expect(team.letter == "A")
                #expect(team.gender.value1 == .masculino)
                #expect(team.modality.value1 == .futbol_7)
                #expect(team.isOwn)
                #expect(team.opponentClubId == nil)
                #expect(team.seasonId == nil, "un propio no lleva temporada (D-104)")
                #expect(team.federationTeamId == nil, "el código del propio va en su inscripción (D-101)")
                #expect(team.clubName == "TEAMREADCLUB")
                #expect(team.displayName == "TEAMREADCLUB Alevín A")
            }
        }
    }

    /// **El rival, con los rótulos de su club**, su temporada y su código.
    @Test("un rival: 200, cada campo, con el nombre de su club")
    func readsAnOpponent() async throws {
        try await Self.withSeededTeams { app, seeded in
            try await Self.get(app, "\(seeded.rival)") { response async throws in
                #expect(response.status == .ok)
                let team = try Self.decodeTeam(response)
                #expect(Self.lower(team.id) == Self.lower(seeded.rival))
                #expect(team.letter == "B")
                #expect(team.isOwn == false)
                #expect(team.opponentClubId.map(Self.lower) == Self.lower(seeded.rivalClub))
                #expect(team.seasonId.map(Self.lower) == Self.lower(seeded.season))
                #expect(team.federationTeamId == "3349087")
                #expect(team.clubName == "Galapagar")
                #expect(team.displayName == "Galapagar Alevín B")
            }
        }
    }

    @Test("un equipo que no existe: 404 TEAM_NOT_FOUND")
    func aMissingTeamIsNotFound() async throws {
        try await Self.withSeededTeams { app, _ in
            try await Self.get(app, "\(TeamID(raw: UUID()))") { response async throws in
                #expect(response.status == .notFound)
                #expect(try Self.decodeProblem(response).code == .TEAM_NOT_FOUND)
            }
        }
    }

    @Test("un teamId que no es un UUID: 400 INVALID_UUID")
    func aTeamIdThatIsNotAUUIDIsABadRequest() async throws {
        try await Self.withSeededTeams { app, _ in
            try await Self.get(app, "abc") { response async throws in
                #expect(response.status == .badRequest)
                #expect(try Self.decodeProblem(response).code == .INVALID_UUID)
            }
        }
    }
}
