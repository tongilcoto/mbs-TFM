import APIContract
import Application
import Domain
import Fluent
import Foundation
import SQLKit
import Testing
import Vapor
import VaporTesting
@testable import App
import TestSupport
@testable import Tenancy

/// Nivel 4 (§8.1): los refuerzos de la plantilla por HTTP (R7.9, la operación 89),
/// contra Postgres. El club es el de `AppearanceEndpointTests`, en su propio *schema*,
/// con el Cadete A inscrito y un jugador del Cadete B que juega con él.
@Suite("Reinforcements · §5.1 · los refuerzos de la plantilla, por HTTP",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct ReinforcementEndpointTests {
    typealias A = AppearanceEndpointTests
    static let slug = "refuerzosclub"
    static var schema: String { "\(A.prefix)\(slug)" }

    static func send(
        _ app: Application, _ method: HTTPMethod, _ path: String, json: String? = nil,
        _ check: @escaping @Sendable (TestingHTTPResponse) async throws -> Void
    ) async throws {
        try await A.send(app, method, path, json: json, slug: slug, check)
    }

    /// La temporada en curso, la inscripción del A en ella, y un jugador del B.
    static func prepare(_ app: Application, _ s: A.Seeded) async throws -> (season: UUID, refuerzo: UUID) {
        let sql = app.db(.control) as! any SQLDatabase
        let season = try await sql.raw(
            "SELECT season_id FROM \(ident: schema).players WHERE id = \(bind: s.juan.raw)"
        ).first(decoding: [String: UUID].self)!["season_id"]!
        let (profile, refuerzo) = (UUID(), UUID())
        try await sql.raw("""
            INSERT INTO \(ident: schema).team_registrations (id, team_id, season_id, created_at, updated_at)
            VALUES (\(bind: UUID()), \(bind: s.cadeteA.raw), \(bind: season), now(), now())
            """).run()
        try await sql.raw("""
            INSERT INTO \(ident: schema).player_profiles (id, full_name, created_at, updated_at)
            VALUES (\(bind: profile), 'LUIS SANZ', now(), now())
            """).run()
        try await sql.raw("""
            INSERT INTO \(ident: schema).players (id, profile_id, team_id, season_id, created_at, updated_at)
            VALUES (\(bind: refuerzo), \(bind: profile), \(bind: s.cadeteB.raw), \(bind: season), now(), now())
            """).run()
        return (season, refuerzo)
    }

    @Test("el refuerzo sale con su equipo, sus actas contadas y su último partido")
    func listsTheReinforcement() async throws {
        try await A.withSeededClub(slug: Self.slug) { app, s in
            let (season, refuerzo) = try await Self.prepare(app, s)
            try await Self.send(app, .POST, "/v1/appearances", json: A.appearanceJSON(
                player: PlayerID(raw: refuerzo), match: s.played, team: s.cadeteA, status: "jugado")) {
                (response: TestingHTTPResponse) async throws in
                #expect(response.status == .created)
            }
            try await Self.send(app, .GET, "/v1/teams/\(s.cadeteA)/registrations/\(season)/reinforcements") {
                (response: TestingHTTPResponse) async throws in
                #expect(response.status == .ok)
                let rows = try A.decode([Components.Schemas.ReinforcementResponse].self, response)
                #expect(rows.count == 1)
                let row = try #require(rows.first)
                #expect(row.playerId == "\(PlayerID(raw: refuerzo))")
                #expect(row.fullName == "LUIS SANZ")
                #expect(row.team.value1.teamId == "\(s.cadeteB)")
                #expect(row.reportCount == 1)
                #expect(row.playedCount == 1)
                #expect(row.convokedWithoutMinutesCount == 0)
                #expect(row.lastMatch.value1.matchId == "\(s.played)")
                #expect(row.lastMatch.value1.roundNumber == 1)
                #expect(row.lastMatch.value1.matchDate == "2025-10-04")
            }
        }
    }

    @Test("sin refuerzos, lista vacía; un equipo sin inscribir, 404 TEAM_NOT_REGISTERED; un id malo, 400")
    func emptyAndErrors() async throws {
        try await A.withSeededClub(slug: Self.slug) { app, s in
            let (season, _) = try await Self.prepare(app, s)
            try await Self.send(app, .GET, "/v1/teams/\(s.cadeteA)/registrations/\(season)/reinforcements") {
                (response: TestingHTTPResponse) async throws in
                #expect(try A.decode([Components.Schemas.ReinforcementResponse].self, response).isEmpty)
            }
            try await Self.send(app, .GET, "/v1/teams/\(s.cadeteB)/registrations/\(season)/reinforcements") {
                (response: TestingHTTPResponse) async throws in
                #expect(response.status == .notFound)
                #expect(try A.code(response) == "TEAM_NOT_REGISTERED")
            }
            try await Self.send(app, .GET, "/v1/teams/nada/registrations/\(season)/reinforcements") {
                (response: TestingHTTPResponse) async throws in
                #expect(response.status == .badRequest)
                #expect(try A.code(response) == "INVALID_UUID")
            }
        }
    }
}
