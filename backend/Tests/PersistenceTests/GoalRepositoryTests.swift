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

/// Nivel 3 (§8.1): el repositorio de los goles (R7.7), contra Postgres.
///
/// Lo que se prueba es el **mapeo** de ida y vuelta, con todo lleno y con todo
/// vacío; **el orden** (por minuto con el partido, por fecha sin él), **la página**
/// y su total, el filtro por **temporada**, que se alcanza por la competición
/// (`D-28`), y que el borrado es **lógico** (`D-36`).
@Suite("Goal · R7.7 · el repositorio de los goles",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct GoalRepositoryTests {

    static let prefix = "test_goalrepo_"
    static let now = Date(timeIntervalSince1970: 1_760_000_000)

    struct Fixture: Sendable {
        let tenant: TenantFixture
        /// El 4 de octubre, y el 11.
        let early: Match
        let late: Match
        let own: TeamID
        let rival: TeamID
        let season: SeasonID
        let juan: PlayerID
        let pedro: PlayerID
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
            func day(_ text: String) -> Date { try! Date("\(text)T00:00:00Z", strategy: .iso8601) }
            let r1 = try Round(id: RoundID(raw: UUID()), competitionID: competition.id, number: 1,
                               startDate: day("2025-10-04"), endDate: day("2025-10-04"), createdAt: now, updatedAt: now)
            let r2 = try Round(id: RoundID(raw: UUID()), competitionID: competition.id, number: 2,
                               startDate: day("2025-10-11"), endDate: day("2025-10-11"), createdAt: now, updatedAt: now)
            let rivalClub = try OpponentClub(
                id: OpponentClubID(raw: UUID()), name: "C.D. RIVAL", shortName: "Rival",
                slug: try Slug("cd-rival"), createdAt: now, updatedAt: now)
            let own = try Team(id: TeamID(raw: UUID()), category: .cadete, letter: "A", gender: .masculino,
                               modality: .futbol11, createdAt: now, updatedAt: now)
            let rival = try Team(id: TeamID(raw: UUID()), opponentClubID: rivalClub.id, seasonID: season.id,
                                 category: .cadete, letter: "A", gender: .masculino, modality: .futbol11,
                                 createdAt: now, updatedAt: now)
            func match(_ round: Round, _ date: String) throws -> Match {
                try Match(id: MatchID(raw: UUID()), competitionID: competition.id, roundID: round.id,
                          kickoff: Kickoff(date: day(date)), homeTeamID: own.id, awayTeamID: rival.id,
                          status: .finalizado, createdAt: now, updatedAt: now)
            }
            let (early, late) = (try match(r1, "2025-10-04"), try match(r2, "2025-10-11"))
            let profiles = try ["Juan García", "Pedro López"].map {
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
                try await r.rounds.save(r1)
                try await r.rounds.save(r2)
                try await r.opponentClubs.save(rivalClub)
                try await r.teams.save(own)
                try await r.teams.save(rival)
                try await r.matches.save(early)
                try await r.matches.save(late)
                for profile in profiles { try await r.playerProfiles.save(profile) }
                for player in players { try await r.players.save(player) }
            }
            try await body(Fixture(tenant: tenant, early: early, late: late, own: own.id, rival: rival.id,
                                   season: season.id, juan: players[0].id, pedro: players[1].id))
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    static func goal(_ f: Fixture, _ match: Match, minute: Int? = nil, scorer: PlayerID? = nil) throws -> Goal {
        Goal(id: GoalID(raw: UUID()), matchID: match.id, scoringTeamID: f.own, concedingTeamID: f.rival,
             scorer: scorer, minute: try minute.map(MatchMinute.init), createdAt: now, updatedAt: now)
    }

    @Test("un gol vuelve como se guardó, con todo lleno y con todo vacío")
    func roundTrip() async throws {
        try await Self.withFixture("goalroundtrip") { f in
            let full = Goal(
                id: GoalID(raw: UUID()), matchID: f.early.id, scoringTeamID: f.own, concedingTeamID: f.rival,
                scorer: f.juan, assist: f.pedro, assisted: true, minute: try MatchMinute(33), zone: .areaChica,
                attackSide: .izquierda, shotSide: .derecha, bodyPart: .pieDerecho, playType: .trasFalta,
                comment: try EntryComment.make("de rebote"), fromReport: true, createdAt: Self.now, updatedAt: Self.now)
            let bare = try Self.goal(f, f.early)
            try await f.tenant.scope { r in
                try await r.goals.save(full)
                try await r.goals.save(bare)
                let back = try #require(try await r.goals.find(full.id))
                #expect(back.scorer == f.juan)
                #expect(back.assist == f.pedro)
                #expect(back.assisted)
                #expect(back.minute?.value == 33)
                #expect(back.zone == .areaChica)
                #expect(back.attackSide == .izquierda)
                #expect(back.shotSide == .derecha)
                #expect(back.bodyPart == .pieDerecho)
                #expect(back.playType == .trasFalta)
                #expect(back.comment?.value == "de rebote")
                #expect(back.fromReport)
                #expect(back.concedingTeamID == f.rival)
                let empty = try #require(try await r.goals.find(bare.id))
                #expect(empty.scorer == nil && empty.minute == nil && empty.playType == nil && empty.comment == nil)
                #expect(!empty.fromReport && !empty.assisted)
            }
        }
    }

    @Test("con el partido, por minuto y los que no tienen al final; sin él, del más reciente al más antiguo")
    func ordering() async throws {
        try await Self.withFixture("goalorder") { f in
            let noMinute = try Self.goal(f, f.early, scorer: f.juan)
            let at80 = try Self.goal(f, f.early, minute: 80, scorer: f.juan)
            let at5 = try Self.goal(f, f.early, minute: 5, scorer: f.juan)
            let later = try Self.goal(f, f.late, minute: 50, scorer: f.juan)
            try await f.tenant.scope { r in
                for goal in [noMinute, at80, at5, later] { try await r.goals.save(goal) }
                let inMatch = try await r.goals.list(GoalFilter(matchID: f.early.id), page: 1, perPage: 25)
                #expect(inMatch.goals.map(\.id) == [at5.id, at80.id, noMinute.id])
                let byScorer = try await r.goals.list(GoalFilter(scorer: f.juan), page: 1, perPage: 25)
                #expect(byScorer.goals.first?.id == later.id)
                #expect(byScorer.total == 4)
            }
        }
    }

    @Test("la página trae los suyos, y el total cuenta todos")
    func pagination() async throws {
        try await Self.withFixture("page") { f in
            try await f.tenant.scope { r in
                for minute in [1, 2, 3] { try await r.goals.save(try Self.goal(f, f.early, minute: minute)) }
                let second = try await r.goals.list(GoalFilter(matchID: f.early.id), page: 2, perPage: 2)
                #expect(second.goals.map { $0.minute?.value } == [3])
                #expect(second.total == 3)
            }
        }
    }

    @Test("el filtro por temporada se alcanza por la competición (D-28)")
    func seasonFilter() async throws {
        try await Self.withFixture("season") { f in
            try await f.tenant.scope { r in
                try await r.goals.save(try Self.goal(f, f.early))
                let here = try await r.goals.list(GoalFilter(scoringTeamID: f.own, seasonID: f.season), page: 1, perPage: 25)
                #expect(here.total == 1)
                let elsewhere = try await r.goals.list(
                    GoalFilter(scoringTeamID: f.own, seasonID: SeasonID(raw: UUID())), page: 1, perPage: 25)
                #expect(elsewhere.total == 0)
            }
        }
    }

    @Test("borrado, el gol deja de verse y sigue en la tabla (D-36)")
    func deleteIsLogical() async throws {
        try await Self.withFixture("goaldelete") { f in
            let goal = try Self.goal(f, f.early)
            try await f.tenant.scope { r in
                try await r.goals.save(goal)
                try await r.goals.delete(goal.id)
                #expect(try await r.goals.find(goal.id) == nil)
                #expect(try await r.goals.list(GoalFilter(matchID: f.early.id), page: 1, perPage: 25).total == 0)
            }
            let rows = try await f.tenant.raw.raw(
                "SELECT count(*)::int AS n FROM \(ident: f.tenant.schema).goals").first(decoding: [String: Int].self)
            #expect(rows?["n"] == 1)
        }
    }
}
