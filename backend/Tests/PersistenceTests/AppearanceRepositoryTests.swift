import Application
import Domain
import Fluent
import Foundation
import SQLKit
import Testing
import Vapor

@testable import App
import TestSupport
@testable import Persistence
@testable import Tenancy

/// Nivel 3 (§8.1): el repositorio de la convocatoria y la copia del acta (R7.6),
/// contra Postgres.
///
/// Lo que se prueba es el **mapeo** de ida y vuelta, el **orden** de la convocatoria
/// (por dorsal, los que no tienen al final), que el borrado es **lógico** (`D-36`),
/// y que la copia del acta se lee como la escribe la carga, **y que guardar el
/// partido no la pisa**.
@Suite("Appearance · R7.6 · el repositorio de la convocatoria y la copia del acta",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct AppearanceRepositoryTests {

    static let prefix = "test_apprepo_"
    static let now = Date(timeIntervalSince1970: 1_760_000_000)

    struct Fixture: Sendable {
        let tenant: TenantFixture
        let match: Match
        let own: Team
        let players: [Player]
    }

    static func withFixture(_ slug: String, _ body: @escaping @Sendable (Fixture) async throws -> Void) async throws {
        try await TestEnvironment.withApp { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(slug, federation: .rffm, schemaPrefix: prefix, on: app)
            let tenant = TenantFixture(app: app, slug: slug, schema: "\(prefix)\(slug)")
            let season = try Season(id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"),
                                    federationSeasonID: nil, createdAt: now, updatedAt: now)
            let competition = try Competition(
                id: CompetitionID(raw: UUID()), seasonID: season.id, modality: .futbol11, gender: .masculino,
                federationCompetitionID: "1", federationGroupID: "2", ageCategory: .cadete,
                divisionLabel: "PRIMERA", groupLabel: "Grupo 1", createdAt: now, updatedAt: now)
            let day = try Date("2025-10-04T00:00:00Z", strategy: .iso8601)
            let round = try Round(id: RoundID(raw: UUID()), competitionID: competition.id, number: 1,
                                  startDate: day, endDate: day, createdAt: now, updatedAt: now)
            let rivalClub = try OpponentClub(
                id: OpponentClubID(raw: UUID()), name: "C.D. RIVAL", shortName: "Rival",
                slug: try Slug("cd-rival"), createdAt: now, updatedAt: now)
            let own = try Team(id: TeamID(raw: UUID()), category: .cadete, letter: "A", gender: .masculino,
                               modality: .futbol11, createdAt: now, updatedAt: now)
            let rival = try Team(id: TeamID(raw: UUID()), opponentClubID: rivalClub.id, seasonID: season.id,
                                 category: .cadete, letter: "A", gender: .masculino, modality: .futbol11,
                                 createdAt: now, updatedAt: now)
            let match = try Match(id: MatchID(raw: UUID()), competitionID: competition.id, roundID: round.id,
                                  kickoff: Kickoff(date: day), homeTeamID: own.id, awayTeamID: rival.id,
                                  status: .finalizado, createdAt: now, updatedAt: now)
            let profiles = try ["Juan García", "Pedro López", "Luis Sanz"].map {
                PlayerProfile(id: PlayerProfileID(raw: UUID()), fullName: try PlayerName($0), birthYear: nil,
                              createdAt: now, updatedAt: now)
            }
            let players = profiles.map {
                Player(id: PlayerID(raw: UUID()), profileID: $0.id, teamID: own.id, seasonID: season.id,
                       createdAt: now, updatedAt: now)
            }
            try await tenant.scope { r in
                try await r.seasons.save(season)
                try await r.competitions.save(competition)
                try await r.rounds.save(round)
                try await r.opponentClubs.save(rivalClub)
                try await r.teams.save(own)
                try await r.teams.save(rival)
                try await r.matches.save(match)
                for profile in profiles { try await r.playerProfiles.save(profile) }
                for player in players { try await r.players.save(player) }
            }
            try await body(Fixture(tenant: tenant, match: match, own: own, players: players))
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    static func row(_ f: Fixture, _ index: Int, _ status: AppearanceStatus, shirt: Int? = nil,
                    minutes: Int? = nil) throws -> Appearance {
        Appearance(id: AppearanceID(raw: UUID()), playerID: f.players[index].id, matchID: f.match.id,
                   teamID: f.own.id, status: status, shirtNumber: try shirt.map(ShirtNumber.init),
                   minutes: try minutes.map(MinutesPlayed.init), createdAt: now, updatedAt: now)
    }

    @Test("una convocatoria vuelve como se guardó, con todo lleno y con todo vacío")
    func roundTrip() async throws {
        try await Self.withFixture("roundtrip") { f in
            let full = try Self.row(f, 0, .jugado, shirt: 7, minutes: 70)
            let bare = try Self.row(f, 1, .bajaMedica)
            try await f.tenant.scope { r in
                try await r.appearances.save(full)
                try await r.appearances.save(bare)
                let back = try #require(try await r.appearances.find(full.id))
                #expect(back.status == .jugado)
                #expect(back.shirtNumber?.value == 7)
                #expect(back.minutes?.value == 70)
                #expect(back.teamID == f.own.id)
                #expect(back.playerID == full.playerID)
                #expect(back.matchID == f.match.id)
                let empty = try #require(try await r.appearances.find(bare.id))
                #expect(empty.shirtNumber == nil)
                #expect(empty.minutes == nil)
            }
        }
    }

    @Test("la convocatoria va por dorsal, y los que no tienen al final")
    func listGoesByShirt() async throws {
        try await Self.withFixture("order") { f in
            try await f.tenant.scope { r in
                try await r.appearances.save(try Self.row(f, 0, .jugado))
                try await r.appearances.save(try Self.row(f, 1, .jugado, shirt: 10))
                try await r.appearances.save(try Self.row(f, 2, .jugado, shirt: 3))
                let order = try await r.appearances.list(matchID: f.match.id, teamID: nil).map(\.playerID)
                #expect(order == [f.players[2].id, f.players[1].id, f.players[0].id])
            }
        }
    }

    @Test("borrada, la convocatoria deja de verse, y el jugador se puede apuntar otra vez (D-36)")
    func deleteIsLogical() async throws {
        try await Self.withFixture("delete") { f in
            let first = try Self.row(f, 0, .convocadoSinMinutos)
            try await f.tenant.scope { r in
                try await r.appearances.save(first)
                try await r.appearances.delete(first.id)
                #expect(try await r.appearances.find(first.id) == nil)
                #expect(try await r.appearances.find(playerID: first.playerID, matchID: f.match.id) == nil)
                #expect(try await r.appearances.list(playerID: first.playerID).isEmpty)
                try await r.appearances.save(try Self.row(f, 0, .sancionado))
            }
            let rows = try await f.tenant.raw.raw(
                "SELECT count(*)::int AS n FROM \(ident: f.tenant.schema).appearances"
            ).first(decoding: [String: Int].self)
            #expect(rows?["n"] == 2, "la borrada sigue en la tabla")
        }
    }

    @Test("la copia del acta se lee como la escribe la carga, y guardar el partido no la pisa (D-133)")
    func reportCopyRoundTripAndSurvivesSave() async throws {
        try await Self.withFixture("copy") { f in
            let before = try await f.tenant.scope { try await $0.matches.reportCopies(of: [f.match.id]) }
            #expect(before.isEmpty)
            let lineup = #"{"players":[{"playerId":"\#(f.players[0].id)","teamId":"\#(f.own.id)","status":"jugado"}]}"#
            try await f.tenant.raw.raw("""
                UPDATE \(ident: f.tenant.schema).matches
                SET report_loaded_at = '2025-10-04T22:00:00Z', report_lineup = \(bind: lineup)::jsonb
                """).run()
            try await f.tenant.scope { r in
                // La ingesta del calendario guarda el partido otra vez.
                try await r.matches.save(try #require(try await r.matches.find(f.match.id)))
                let copy = try #require(try await r.matches.reportCopies(of: [f.match.id])[f.match.id])
                #expect(copy.loadedAt == (try Date("2025-10-04T22:00:00Z", strategy: .iso8601)))
                #expect(copy.lineup == [ReportLineupEntry(playerID: f.players[0].id, teamID: f.own.id, status: .jugado)])
            }
        }
    }

    /// La carga del acta escribe la copia (R7.12, `D-133`, `D-134`): la fecha y la convocatoria, en un documento; y
    /// guardar el partido después no la pisa.
    @Test("la carga escribe la copia del acta, se lee igual, y guardar el partido no la pisa (R7.12)")
    func reportCopyIsWritten() async throws {
        try await Self.withFixture("copywrite") { f in
            let loadedAt = try Date("2025-10-04T22:00:00Z", strategy: .iso8601)
            let lineup = [
                ReportLineupEntry(playerID: f.players[0].id, teamID: f.own.id, status: .jugado),
                ReportLineupEntry(playerID: f.players[1].id, teamID: f.own.id, status: .convocadoSinMinutos),
            ]
            try await f.tenant.scope { r in
                try await r.matches.saveReportCopy(MatchReportCopy(loadedAt: loadedAt, lineup: lineup), for: f.match.id)
                try await r.matches.save(try #require(try await r.matches.find(f.match.id)))
            }
            let copy = try #require(
                try await f.tenant.scope { try await $0.matches.reportCopies(of: [f.match.id]) }[f.match.id])
            #expect(copy.loadedAt == loadedAt)
            #expect(copy.lineup == lineup)
        }
    }
}
