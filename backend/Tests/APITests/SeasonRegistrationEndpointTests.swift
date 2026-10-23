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

/// Nivel 4 (§8.1): `GET /v1/seasons/{seasonId}/registrations` (`D-102`; Plan R1,
/// R1.9). La agrupación por equipo y el orden los prueba el nivel 2; aquí se
/// prueba **el borde**: la ruta, cada campo del equipo y de la inscripción, el 404
/// y el 400.
@Suite("SeasonRegistrations · D-102 · el equipo en una temporada",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct SeasonRegistrationEndpointTests {

    static let prefix = "e2e_"
    static let slug = "seasregclub"
    static let createdAt = Date(timeIntervalSince1970: 1_760_000_000)

    struct Seeded: Sendable {
        let season: SeasonID, competition: CompetitionID
        let cadeteB: TeamID, alevinA: TeamID
    }

    static func withSeededClub(
        _ body: @escaping @Sendable (Application, Seeded) async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(slug, federation: .rffm, schemaPrefix: prefix, on: app)

            let seeded = Seeded(
                season: SeasonID(raw: UUID()), competition: CompetitionID(raw: UUID()),
                cadeteB: TeamID(raw: UUID()), alevinA: TeamID(raw: UUID()))
            let unitOfWork = FluentTenantUnitOfWork(controlDatabase: app.db(.control))
            try await unitOfWork.withRepositories(actor: ActorContext(clubSlug: try Slug(slug))) {
                try await $0.seasons.save(try Season(
                    id: seeded.season, label: try SeasonLabel("2026/27"), federationSeasonID: "22",
                    createdAt: createdAt, updatedAt: createdAt))
                try await $0.competitions.save(try Competition(
                    id: seeded.competition, seasonID: seeded.season, modality: .futbol11,
                    gender: .masculino, federationCompetitionID: "26737751", federationGroupID: "26737755",
                    ageCategory: .cadete, divisionLabel: "PRIMERA CADETE", groupLabel: "Grupo 4",
                    createdAt: createdAt, updatedAt: createdAt))
                // El Cadete B se guarda **antes** que el Alevín A: el orden de la
                // respuesta tiene que salir de la regla, no de cómo se guardó.
                let cadeteB = try Team(
                    id: seeded.cadeteB, opponentClubID: nil, category: .cadete, letter: "B",
                    gender: .masculino, modality: .futbol11, createdAt: createdAt, updatedAt: createdAt)
                let alevinA = try Team(
                    id: seeded.alevinA, opponentClubID: nil, category: .alevin, letter: "A",
                    gender: .femenino, modality: .futbol7, createdAt: createdAt, updatedAt: createdAt)
                try await $0.teams.save(cadeteB)
                try await $0.teams.save(alevinA)
                try await $0.teamRegistrations.save(try TeamRegistration(
                    id: TeamRegistrationID(raw: UUID()), team: cadeteB, seasonID: seeded.season,
                    competitionID: seeded.competition, federationTeamID: "821",
                    createdAt: createdAt, updatedAt: createdAt))
                try await $0.teamRegistrations.save(try TeamRegistration(
                    id: TeamRegistrationID(raw: UUID()), team: alevinA, seasonID: seeded.season,
                    createdAt: createdAt, updatedAt: createdAt))
            }

            try await body(app, seeded)
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    static func decode(_ response: TestingHTTPResponse) throws -> [Components.Schemas.TeamRegistrationResponse] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            [Components.Schemas.TeamRegistrationResponse].self, from: Data(response.body.readableBytesView))
    }

    static func problem(_ response: TestingHTTPResponse) throws -> Components.Schemas.Problem {
        try JSONDecoder().decode(Components.Schemas.Problem.self, from: Data(response.body.readableBytesView))
    }

    static func header(_ request: inout TestingHTTPRequest) {
        request.headers.add(name: "X-Club", value: slug)
    }

    // ─────────────────────────────────────────────────────────────────────────

    /// El Alevín A, inscrito sin competición (junio), sale **con la lista vacía**,
    /// y delante del Cadete B por la edad.
    @Test("un elemento por equipo, en orden, con sus competiciones y la de junio vacía")
    func listsTheTeamsOfTheSeason() async throws {
        try await Self.withSeededClub { app, seeded in
            try await app.testing().test(
                .GET, "/v1/seasons/\(seeded.season)/registrations", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                #expect(response.status == .ok)
                let entries = try Self.decode(response)
                #expect(entries.map(\.team.id) == ["\(seeded.alevinA)", "\(seeded.cadeteB)"])
                #expect(entries.map(\.seasonId) == ["\(seeded.season)", "\(seeded.season)"])
                try #require(entries.count == 2)
                #expect(entries[0].competitions.isEmpty)
                let competition = try #require(entries[1].competitions.first)
                #expect(competition.competitionId == "\(seeded.competition)")
                #expect(competition.federationTeamId == "821")
            }
        }
    }

    /// Cada campo del equipo. **El código de la federación del equipo propio va
    /// en la inscripción** (`D-101`), así que en el equipo es nulo.
    @Test("cada campo del equipo sale con su valor, y el club con su nombre corto")
    func mapsEveryTeamField() async throws {
        try await Self.withSeededClub { app, seeded in
            try await app.testing().test(
                .GET, "/v1/seasons/\(seeded.season)/registrations", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                let team = try #require(try Self.decode(response).last).team
                #expect(team.id == "\(seeded.cadeteB)")
                #expect(team.category == .cadete)
                #expect(team.letter == "B")
                #expect(team.gender.value1 == .masculino)
                #expect(team.modality.value1 == .futbol_11)
                #expect(team.opponentClubId == nil)
                #expect(team.federationTeamId == nil)
                // `D-104`: un propio no tiene temporada; la suya va en la inscripción.
                #expect(team.seasonId == nil)
                #expect(team.isOwn)
                #expect(team.clubName == "SEASREGCLUB")
                #expect(team.displayName == "SEASREGCLUB Cadete B")
                #expect(team.crestUrl == nil)
            }
        }
    }

    @Test("una temporada que no existe es 404 SEASON_NOT_FOUND")
    func anUnknownSeasonIs404() async throws {
        try await Self.withSeededClub { app, _ in
            try await app.testing().test(
                .GET, "/v1/seasons/\(UUID())/registrations", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                #expect(response.status == .notFound)
                #expect(try Self.problem(response).code == .SEASON_NOT_FOUND)
            }
        }
    }

    @Test("un seasonId que no es un UUID es 400 INVALID_UUID")
    func aSeasonIdThatIsNotAUUIDIs400() async throws {
        try await Self.withSeededClub { app, _ in
            try await app.testing().test(
                .GET, "/v1/seasons/abc/registrations", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                #expect(response.status == .badRequest)
                #expect(try Self.problem(response).code == .INVALID_UUID)
            }
        }
    }
}
