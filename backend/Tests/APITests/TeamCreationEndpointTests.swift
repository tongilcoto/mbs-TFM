import APIContract
import Application
import Domain
import Fluent
import Foundation
import Synchronization
import Testing
import Vapor
import VaporTesting
@testable import App
import TestSupport
@testable import Persistence
@testable import Tenancy

/// Nivel 4 (§8.1): `POST /v1/teams` (R2.9, `D-107`). El caso de uso está probado en
/// el nivel 2; aquí, **el borde**: la ruta, el 201 frente al 200, cada campo de la
/// respuesta, lo que queda escrito en Postgres y cada error con su código.
@Suite("Teams · §5.1 · el alta de equipo, que inscribe al que ya existe (D-107)",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct TeamCreationEndpointTests {

    static let prefix = "e2e_"
    static let slug = "teamsclub"
    static let now = Date(timeIntervalSince1970: 1_760_000_000)

    struct Seeded {
        let thisSeason: SeasonID   // 2027/28, sin código: la que el club acaba de crear
        let lastSeason: SeasonID   // 2026/27
    }

    static func withSeededClub(
        _ body: @escaping @Sendable (Application, Seeded) async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(slug, federation: .rffm, schemaPrefix: prefix, on: app)
            let seeded = Seeded(thisSeason: SeasonID(raw: UUID()), lastSeason: SeasonID(raw: UUID()))
            try await unitOfWork(app).withRepositories(actor: actor()) {
                try await $0.seasons.save(try Season(
                    id: seeded.thisSeason, label: try SeasonLabel("2027/28"),
                    federationSeasonID: nil, createdAt: now, updatedAt: now))
                try await $0.seasons.save(try Season(
                    id: seeded.lastSeason, label: try SeasonLabel("2026/27"),
                    federationSeasonID: "22", createdAt: now, updatedAt: now))
            }
            try await body(app, seeded)
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    static func unitOfWork(_ app: Application) -> FluentTenantUnitOfWork {
        FluentTenantUnitOfWork(controlDatabase: app.db(.control))
    }

    static func actor() throws -> ActorContext { ActorContext(clubSlug: try Slug(slug)) }

    static func post(
        _ app: Application, season: String, letter: String? = "A",
        _ check: @escaping @Sendable (TestingHTTPResponse) async throws -> Void
    ) async throws {
        let letterJSON = letter.map { "\"\($0)\"" } ?? "null"
        let json = #"{"category": "alevin", "letter": \#(letterJSON), "gender": "masculino", "modality": "futbol_7", "seasonId": "\#(season)"}"#
        try await app.testing().test(
            .POST, "/v1/teams",
            beforeRequest: { request in
                request.headers.add(name: "X-Club", value: slug)
                request.headers.contentType = .json
                request.body = ByteBuffer(string: json)
            }, afterResponse: check)
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

    static func registrations(_ teamID: String, on app: Application) async throws -> [SeasonID] {
        let id = TeamID(raw: try #require(UUID(uuidString: teamID)))
        return try await unitOfWork(app).withRepositories(actor: actor()) { repositories in
            var seasons: [SeasonID] = []
            for season in try await repositories.seasons.list(includingArchived: true) {
                if !(try await repositories.teamRegistrations.list(teamID: id, seasonID: season.id)).isEmpty {
                    seasons.append(season.id)
                }
            }
            return seasons
        }
    }

    @Test("un equipo nuevo: 201, cada campo, e inscrito en la temporada (D-66, D-68)")
    func createsANewTeam() async throws {
        try await Self.withSeededClub { app, seeded in
            try await Self.post(app, season: "\(seeded.thisSeason)") { response async throws in
                #expect(response.status == .created)
                let team = try Self.decodeTeam(response)
                #expect(team.category == .alevin)
                #expect(team.letter == "A")
                #expect(team.gender.value1 == .masculino)
                #expect(team.modality.value1 == .futbol_7)
                #expect(team.isOwn)
                #expect(team.opponentClubId == nil)
                #expect(team.seasonId == nil, "un propio no lleva temporada (D-104)")
                #expect(team.federationTeamId == nil)
                #expect(team.displayName.hasSuffix(" A"))
                let seasons = try await Self.registrations(team.id, on: app)
                #expect(seasons == [seeded.thisSeason])
            }
        }
    }

    /// **`D-107`**: el mismo equipo, otra temporada. Mismo `id`, una inscripción más.
    @Test("el mismo equipo en otra temporada: 200, el mismo id, y queda inscrito en las dos (D-107)")
    func registersAnExistingTeamInAnotherSeason() async throws {
        try await Self.withSeededClub { app, seeded in
            let first = Mutex<String>("")
            try await Self.post(app, season: "\(seeded.lastSeason)") { response async throws in
                #expect(response.status == .created)
                let id = try Self.decodeTeam(response).id
                first.withLock { $0 = id }
            }
            let firstID = first.withLock { $0 }
            try await Self.post(app, season: "\(seeded.thisSeason)") { response async throws in
                #expect(response.status == .ok)
                #expect(try Self.decodeTeam(response).id == firstID)
            }
            let seasons = try await Self.registrations(firstID, on: app)
            #expect(Set(seasons) == [seeded.lastSeason, seeded.thisSeason])
        }
    }

    @Test("el mismo equipo ya inscrito en esa temporada: 409 TEAM_ALREADY_REGISTERED (D-107)")
    func aTeamAlreadyInThatSeasonIsAConflict() async throws {
        try await Self.withSeededClub { app, seeded in
            try await Self.post(app, season: "\(seeded.thisSeason)") { response async throws in
                #expect(response.status == .created)
            }
            try await Self.post(app, season: "\(seeded.thisSeason)") { response async throws in
                #expect(response.status == .conflict)
                let problem = try Self.decodeProblem(response)
                #expect(problem.code == .TEAM_ALREADY_REGISTERED)
                #expect(problem.detail?.contains("\(seeded.thisSeason)") == true)
            }
        }
    }

    @Test("una temporada que no existe: 404 SEASON_NOT_FOUND")
    func anUnknownSeasonIsNotFound() async throws {
        try await Self.withSeededClub { app, _ in
            let alien = UUID().uuidString.lowercased()
            try await Self.post(app, season: alien) { response async throws in
                #expect(response.status == .notFound)
                let problem = try Self.decodeProblem(response)
                #expect(problem.code == .SEASON_NOT_FOUND)
                #expect(problem.detail == alien)
            }
        }
    }

    @Test("un seasonId que no es un UUID: 400 INVALID_UUID")
    func aSeasonIdThatIsNotAUUIDIsABadRequest() async throws {
        try await Self.withSeededClub { app, _ in
            try await Self.post(app, season: "abc") { response async throws in
                #expect(response.status == .badRequest)
                #expect(try Self.decodeProblem(response).code == .INVALID_UUID)
            }
        }
    }

    @Test("una letra que solo tiene espacios: 422 INVALID_VALUE con letter en el detail")
    func aBlankLetterIsRejected() async throws {
        try await Self.withSeededClub { app, seeded in
            try await Self.post(app, season: "\(seeded.thisSeason)", letter: " ") { response async throws in
                #expect(response.status == .unprocessableEntity)
                let problem = try Self.decodeProblem(response)
                #expect(problem.code == .INVALID_VALUE)
                #expect(problem.detail?.hasPrefix("letter: ") == true)
            }
        }
    }
}
