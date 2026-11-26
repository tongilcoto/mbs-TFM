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

/// Nivel 3 (§8.1): **la carga del acta contra Postgres** (R7.12, D-138), con la federación falseada. Lo que aquí se
/// prueba y no en el nivel 2: que lo que escribe la carga cumple las restricciones de la base —los `CHECK` de la
/// convocatoria, el gol y la tarjeta, los índices únicos y las claves ajenas—, que todo va en la transacción del acta,
/// y que la copia y la fila de la pasada se leen como se escribieron.
@Suite("La carga del acta · R7.12 · D-138 · contra Postgres",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct MatchReportIngestionTests {

    static let prefix = "test_reportload_"
    /// 2025-10-05, el día siguiente al partido: la temporada 2025/26 está en curso.
    static let now = Date(timeIntervalSince1970: 1_759_665_600)

    /// La federación de mentira: el acta «5589189», y nada más.
    struct ReportClient: FederationClient {
        let report: FederationMatchReport

        func fetchMatchReport(federationMatchID: String) async throws -> FederationMatchReport {
            guard federationMatchID == "5589189" else {
                throw FederationError.coordinateNotFound(detail: "sin preparar: \(federationMatchID)")
            }
            return report
        }
        func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar {
            throw FederationError.coordinateNotFound(detail: "sin calendario")
        }
        func fetchStandings(_ coordinate: FederationCoordinate, round: Int) async throws -> FederationStanding {
            throw FederationError.coordinateNotFound(detail: "sin clasificación")
        }
        func fetchScorers(_ coordinate: FederationCoordinate) async throws -> FederationScorerTable {
            throw FederationError.coordinateNotFound(detail: "sin goleadores")
        }
        func coordinate(fromCalendarURL url: String) throws -> FederationCoordinate {
            throw FederationError.coordinateNotFound(detail: "sin URL")
        }
    }

    static func player(_ side: FederationReportSide, _ code: String, _ published: String, _ full: String,
                       shirt: Int, starter: Bool = true, cameOn: Bool = false) -> FederationReportPlayer {
        FederationReportPlayer(side: side, federationPlayerID: code, publishedName: published, fullName: full,
                               shirtNumber: shirt, isStarter: starter, cameOn: cameOn)
    }

    /// Un acta 2-1 con de todo: titulares, uno que entra y uno que no; un penalti, un gol normal y uno en propia
    /// puerta del rival; una amarilla, una roja por doble amarilla y una tarjeta del rival.
    static let report = FederationMatchReport(
        isClosed: true, homeTeamFederationID: "821", awayTeamFederationID: "900", homeScore: 2, awayScore: 1,
        players: [
            player(.home, "11", "GARCÍA, JUAN", "JUAN GARCÍA", shirt: 9),
            player(.home, "12", "LÓPEZ, PEDRO", "PEDRO LÓPEZ", shirt: 4),
            player(.home, "13", "SANZ, LUIS", "LUIS SANZ", shirt: 14, starter: false, cameOn: true),
            player(.home, "14", "RUIZ, ÓSCAR", "ÓSCAR RUIZ", shirt: 16, starter: false),
            player(.away, "91", "PÉREZ, ANA", "ANA PÉREZ", shirt: 7),
        ],
        goals: [
            FederationReportGoal(side: .home, federationPlayerID: "11", publishedName: "GARCÍA, JUAN", minute: 17,
                                 playType: .penalti),
            FederationReportGoal(side: .away, federationPlayerID: "91", publishedName: "PÉREZ, ANA", minute: 30,
                                 playType: nil),
            FederationReportGoal(side: .home, federationPlayerID: "91", publishedName: "PÉREZ, ANA", minute: 80,
                                 playType: .enPropiaPuerta),
        ],
        cards: [
            FederationReportCard(side: .home, federationPlayerID: "12", publishedName: "LÓPEZ, PEDRO", minute: 20,
                                 type: .amarilla, isSecondYellow: false),
            FederationReportCard(side: .home, federationPlayerID: "13", publishedName: "SANZ, LUIS", minute: 75,
                                 type: .roja, isSecondYellow: true),
            FederationReportCard(side: .away, federationPlayerID: "91", publishedName: "PÉREZ, ANA", minute: 60,
                                 type: .roja, isSecondYellow: false),
        ],
        skipped: [])

    @Test("un acta entera se carga en la base: convocatoria, goles, tarjetas, altas, copia y la fila de la pasada")
    func loadsAWholeReport() async throws {
        let slug = "reportload"
        try await TestEnvironment.withApp { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: Self.prefix, on: app)
            try await TestEnvironment.provisionClub(slug, federation: .rffm, schemaPrefix: Self.prefix, on: app)
            let tenant = TenantFixture(app: app, slug: slug, schema: "\(Self.prefix)\(slug)")
            let now = Self.now
            let season = try Season(id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"),
                                    federationSeasonID: "21", createdAt: now, updatedAt: now)
            let competition = try Competition(
                id: CompetitionID(raw: UUID()), seasonID: season.id, modality: .futbol11, gender: .masculino,
                federationCompetitionID: "1", federationGroupID: "2", ageCategory: .cadete,
                divisionLabel: "PRIMERA", groupLabel: "Grupo 1", createdAt: now, updatedAt: now)
            let day = try Date("2025-10-04T00:00:00Z", strategy: .iso8601)
            let round = try Round(id: RoundID(raw: UUID()), competitionID: competition.id, number: 1,
                                  startDate: day, endDate: day, createdAt: now, updatedAt: now)
            let rivalClub = try OpponentClub(id: OpponentClubID(raw: UUID()), name: "C.D. RIVAL", shortName: "Rival",
                                             slug: try Slug("cd-rival"), createdAt: now, updatedAt: now)
            let own = try Team(id: TeamID(raw: UUID()), category: .cadete, letter: "A", gender: .masculino,
                               modality: .futbol11, createdAt: now, updatedAt: now)
            let rival = try Team(id: TeamID(raw: UUID()), opponentClubID: rivalClub.id, seasonID: season.id,
                                 category: .cadete, letter: "A", gender: .masculino, modality: .futbol11,
                                 federationTeamID: "900", createdAt: now, updatedAt: now)
            let match = try Match(id: MatchID(raw: UUID()), competitionID: competition.id, roundID: round.id,
                                  kickoff: Kickoff(date: day, time: WallClockTime(hour: 11, minute: 0)),
                                  homeTeamID: own.id, awayTeamID: rival.id, status: .finalizado,
                                  federationMatchID: "5589189", createdAt: now, updatedAt: now)
            // Juan ya está en la plantilla, sin código: casa por el nombre y se le guarda.
            let juan = PlayerProfile(id: PlayerProfileID(raw: UUID()), fullName: try PlayerName("Juan García"),
                                     birthYear: nil, createdAt: now, updatedAt: now)
            let juanRow = Player(id: PlayerID(raw: UUID()), profileID: juan.id, teamID: own.id, seasonID: season.id,
                                 createdAt: now, updatedAt: now)
            try await tenant.scope { r in
                try await r.seasons.save(season)
                try await r.competitions.save(competition)
                try await r.rounds.save(round)
                try await r.opponentClubs.save(rivalClub)
                try await r.teams.save(own)
                try await r.teams.save(rival)
                try await r.teamRegistrations.save(try TeamRegistration(
                    id: TeamRegistrationID(raw: UUID()), team: own, seasonID: season.id,
                    competitionID: competition.id, federationTeamID: "821", createdAt: now, updatedAt: now
                ).rosterSynced(at: now))
                try await r.matches.save(match)
                try await r.playerProfiles.save(juan)
                try await r.players.save(juanRow)
            }

            let run = try #require(try await IngestMatchReports(
                unitOfWork: FluentTenantUnitOfWork(controlDatabase: app.db(.control)),
                federation: ReportClient(report: Self.report), clock: FixedInstantClock(instant: now),
                ids: SystemUUIDProvider(), names: FixedNameDictionary(CastilianNames(text: "ÓSCAR"))
            ).execute(competitionID: competition.id, actor: ActorContext(clubSlug: try Slug(slug), isSystem: true)))

            #expect(run.matchReportsLoaded == 1 && run.matchReportsFailed == 0 && run.skipped.isEmpty,
                    "\(run.skipped)")
            #expect(run.matchReportPlayersAdded == 3, "Pedro, Luis y Óscar; Juan ya estaba")

            try await tenant.scope { r in
                // Los jugadores: cuatro filas, y Juan con su código.
                #expect(try await r.players.list(teamID: own.id, seasonID: season.id).count == 4)
                #expect(try await r.playerProfiles.find(juan.id)?.federationPlayerID == "11")
                // La convocatoria.
                let lineup = try await r.appearances.list(matchID: match.id, teamID: nil)
                #expect(lineup.count == 4)
                #expect(lineup.filter { $0.status == .jugado }.count == 3)
                #expect(lineup.filter { $0.status == .convocadoSinMinutos }.count == 1)
                #expect(lineup.first { $0.playerID == juanRow.id }?.shirtNumber?.value == 9)
                // Los goles: 2-1, todos del acta.
                let goals = try await r.goals.list(GoalFilter(matchID: match.id), page: 1, perPage: 50).goals
                #expect(goals.count == 3)
                #expect(goals.filter { $0.scoringTeamID == own.id }.count == 2)
                #expect(goals.first { $0.playType == .penalti }?.scorer == juanRow.id)
                #expect(goals.first { $0.playType == .enPropiaPuerta }?.scorer == nil)
                #expect(goals.allSatisfy { $0.fromReport })
                // Las tarjetas: las dos del club; la del rival, no.
                let cards = try await r.cards.list(matchID: match.id, teamID: nil, playerID: nil)
                #expect(cards.count == 2)
                #expect(cards.contains { $0.type == .roja && $0.isSecondYellow })
                #expect(cards.allSatisfy { $0.fromReport && $0.teamID == own.id })
                // La copia y la marca.
                let copy = try #require(try await r.matches.reportCopies(of: [match.id])[match.id])
                #expect(copy.loadedAt == now && copy.lineup.count == 4)
                // Y la fila de la pasada, como se escribió.
                let stored = try await r.ingestionRuns.list(competitionID: competition.id, limit: 5)
                #expect(stored.map(\.kind) == [.matchReports])
                #expect(stored.first?.matchReportsLoaded == 1 && stored.first?.matchReportPlayersAdded == 3)
            }
            try await TestEnvironment.dropClubs([slug], schemaPrefix: Self.prefix, on: app)
        }
    }
}
