import Domain
import Foundation
import Testing
@testable import Application

/// Nivel 2 (§8.1): `GetStanding` con los repositorios en memoria (R4.7). La racha
/// la prueba el nivel 1 (`FormTests`); aquí, lo que decide el caso de uso: la
/// tabla de esa jornada y no de otra, por puesto, cada equipo con los nombres de
/// **su** club, la racha **hasta esa jornada**, la tabla vacía y el 404.
@Suite("GetStanding · D-34 · la clasificación de una jornada")
struct GetStandingTests {

    static let epoch = Date(timeIntervalSince1970: 0)
    static let actor = ListSeasonRegistrationsTests.actor
    static let club = ListSeasonRegistrationsTests.club

    struct Seeded {
        let store: IngestionStore
        let rounds: [Round]
        let own: Team, rival: Team
        let rivalClub: OpponentClub
    }

    /// Un equipo propio y un rival; tres jornadas: la 1 y la 2 jugadas, con su
    /// tabla, y la 3 sin jugar. La tabla de la 2 se guarda **con el segundo
    /// primero**, y la de la 1 al revés que la de la 2.
    static func seed() async throws -> Seeded {
        let competition = CompetitionID(raw: UUID())
        let season = SeasonID(raw: UUID())
        let rivalClub = try OpponentClub(
            id: OpponentClubID(raw: UUID()), name: "C.D. GALAPAGAR", shortName: "Galapagar",
            slug: try Slug("c-d-galapagar"), createdAt: epoch, updatedAt: epoch)
        let own = try Team(
            id: TeamID(raw: UUID()), category: .cadete, letter: "A", gender: .masculino, modality: .futbol11,
            createdAt: epoch, updatedAt: epoch)
        let rival = try Team(
            id: TeamID(raw: UUID()), opponentClubID: rivalClub.id, seasonID: season, category: .cadete,
            letter: "B", gender: .masculino, modality: .futbol11, createdAt: epoch, updatedAt: epoch)
        let rounds = try (1...3).map {
            try Round(
                id: RoundID(raw: UUID()), competitionID: competition, number: $0, startDate: epoch,
                endDate: epoch, createdAt: epoch, updatedAt: epoch)
        }
        func match(_ round: Int, _ home: Team, _ away: Team, _ score: (Int, Int)?) throws -> Match {
            try Match(
                id: MatchID(raw: UUID()), competitionID: competition, roundID: rounds[round - 1].id,
                kickoff: Kickoff(date: epoch), homeTeamID: home.id, awayTeamID: away.id,
                result: try score.map { try MatchResult(homeScore: $0.0, awayScore: $0.1) },
                status: score == nil ? .programado : .finalizado, createdAt: epoch, updatedAt: epoch)
        }
        func row(_ round: Int, _ team: Team, position: Int, previous: Int?, points: Int) throws -> StandingRow {
            try StandingRow(
                id: StandingRowID(raw: UUID()), competitionID: competition, roundID: rounds[round - 1].id,
                teamID: team.id, position: position, previousPosition: previous, played: round, won: points / 3,
                drawn: 0, lost: round - points / 3, goalsFor: 3, goalsAgainst: 2, points: points,
                createdAt: epoch, updatedAt: epoch)
        }
        let store = IngestionStore()
        await store.seed(club: club)
        await store.seed(
            rounds: rounds, opponentClubs: [rivalClub], teams: [own, rival],
            matches: [
                try match(1, own, rival, (2, 0)), try match(2, rival, own, (3, 1)), try match(3, own, rival, nil),
            ],
            standingRows: [
                try row(2, own, position: 2, previous: 1, points: 3), try row(2, rival, position: 1, previous: 2, points: 3),
                try row(1, own, position: 1, previous: nil, points: 3), try row(1, rival, position: 2, previous: nil, points: 0),
            ])
        return Seeded(store: store, rounds: rounds, own: own, rival: rival, rivalClub: rivalClub)
    }

    static func useCase(_ store: IngestionStore) -> GetStanding {
        GetStanding(
            clubs: FakeClubRepository(store: store), rounds: FakeRoundRepository(store: store),
            standingRows: FakeStandingRowRepository(store: store), matches: FakeMatchRepository(store: store),
            teams: FakeTeamRepository(store: store), opponentClubs: FakeOpponentClubRepository(store: store))
    }

    @Test("la tabla de esa jornada, por puesto, con la fila guardada")
    func theTableOfTheRound() async throws {
        let seeded = try await Self.seed()
        let lines = try await Self.useCase(seeded.store).execute(actor: Self.actor, roundID: seeded.rounds[1].id)
        #expect(lines.map(\.row.teamID) == [seeded.rival.id, seeded.own.id])
        #expect(lines.map(\.row.position) == [1, 2])
        #expect(lines.map(\.row.previousPosition) == [2, 1])
        #expect(lines.allSatisfy { $0.row.roundID == seeded.rounds[1].id })
    }

    @Test("cada equipo con los nombres de su club: el propio y el rival")
    func eachTeamWithItsClub() async throws {
        let seeded = try await Self.seed()
        let lines = try await Self.useCase(seeded.store).execute(actor: Self.actor, roundID: seeded.rounds[1].id)
        #expect(lines.map(\.team) == [
            LabeledTeam(team: seeded.rival, clubName: "C.D. GALAPAGAR", clubShortName: "Galapagar"),
            LabeledTeam(team: seeded.own, clubName: Self.club.name, clubShortName: Self.club.shortName),
        ])
    }

    @Test("la racha de cada uno, hasta esa jornada y no más")
    func theFormUpToTheRound() async throws {
        let seeded = try await Self.seed()
        let lines = try await Self.useCase(seeded.store).execute(actor: Self.actor, roundID: seeded.rounds[1].id)
        #expect(lines.map(\.form) == [
            [FormEntry(roundNumber: 2, outcome: .win), FormEntry(roundNumber: 1, outcome: .loss)],
            [FormEntry(roundNumber: 2, outcome: .loss), FormEntry(roundNumber: 1, outcome: .win)],
        ])
        let first = try await Self.useCase(seeded.store).execute(actor: Self.actor, roundID: seeded.rounds[0].id)
        #expect(first.map(\.form) == [
            [FormEntry(roundNumber: 1, outcome: .win)], [FormEntry(roundNumber: 1, outcome: .loss)],
        ])
    }

    @Test("una jornada sin tabla todavía da la lista vacía")
    func aRoundWithoutTable() async throws {
        let seeded = try await Self.seed()
        let lines = try await Self.useCase(seeded.store).execute(actor: Self.actor, roundID: seeded.rounds[2].id)
        #expect(lines.isEmpty)
    }

    @Test("una jornada que no existe es roundNotFound")
    func anUnknownRound() async throws {
        let seeded = try await Self.seed()
        let missing = RoundID(raw: UUID())
        await #expect(throws: ApplicationError.roundNotFound(id: "\(missing)")) {
            _ = try await Self.useCase(seeded.store).execute(actor: Self.actor, roundID: missing)
        }
    }
}
