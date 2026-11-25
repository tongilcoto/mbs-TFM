import Domain
import Foundation
import Testing
@testable import Application

/// Nivel 2 (§8.1): los refuerzos de la plantilla (R7.9, `D-128`, punto 4), con los
/// repositorios falseados. Reutiliza el club de `AppearanceUseCaseTests`: el Cadete A
/// juega en casa a las 18:00 del 4 de octubre, y el refuerzo es del Cadete B.
@Suite("Reinforcements · R7.9 · los refuerzos de la plantilla, contados")
struct ReinforcementUseCaseTests {
    typealias A = AppearanceUseCaseTests

    static func list(_ s: A.Seeded) -> ListTeamReinforcements {
        let store = s.store
        return ListTeamReinforcements(
            clubs: FakeClubRepository(store: store), seasons: FakeSeasonRepository(store: store),
            teams: FakeTeamRepository(store: store), opponentClubs: FakeOpponentClubRepository(store: store),
            registrations: FakeTeamRegistrationRepository(store: store), players: FakePlayerRepository(store: store),
            profiles: FakePlayerProfileRepository(store: store), appearances: FakeAppearanceRepository(store: store),
            matches: FakeMatchRepository(store: store), rounds: FakeRoundRepository(store: store))
    }

    /// Lo que la siembra de la convocatoria no trae: los perfiles, la inscripción y un
    /// segundo partido del A, el 11 de octubre.
    static func seed() async throws -> (A.Seeded, Match) {
        let s = try await A.seed()
        for (player, name) in [(s.juan, "Juan García"), (s.pedro, "Pedro López"), (s.refuerzo, "Luis Sanz")] {
            await s.store.save(PlayerProfile(id: player.profileID, fullName: try PlayerName(name),
                                             birthYear: nil, createdAt: A.epoch, updatedAt: A.epoch))
        }
        let vigente = s.juan.seasonID
        await s.store.seed(teamRegistrations: [try TeamRegistration(
            id: TeamRegistrationID(raw: UUID()), team: s.cadeteA, seasonID: vigente, createdAt: A.epoch,
            updatedAt: A.epoch)])
        let round2 = try Round(id: RoundID(raw: UUID()), competitionID: s.match.competitionID, number: 2,
                               startDate: ListMatchesTests.day("2025-10-11"), endDate: ListMatchesTests.day("2025-10-11"),
                               createdAt: A.epoch, updatedAt: A.epoch)
        let second = try Match(id: MatchID(raw: UUID()), competitionID: s.match.competitionID, roundID: round2.id,
                               kickoff: Kickoff(date: ListMatchesTests.day("2025-10-11")), homeTeamID: s.rival.id,
                               awayTeamID: s.cadeteA.id, status: .programado, createdAt: A.epoch, updatedAt: A.epoch)
        await s.store.seed(rounds: [round2], matches: [second])
        return (s, second)
    }

    @Test("un jugador de otro equipo que ha jugado con este es un refuerzo, contado y con su último partido")
    func countsTheReinforcement() async throws {
        let (s, second) = try await Self.seed()
        try await A.recorded(s, s.refuerzo, .jugado)
        try await A.recorded(s, s.refuerzo, .convocadoSinMinutos, match: second)
        try await A.recorded(s, s.juan, .jugado)
        let rows = try await Self.list(s).execute(actor: A.actor, teamID: s.cadeteA.id, seasonID: s.juan.seasonID)
        #expect(rows.count == 1)
        let refuerzo = try #require(rows.first)
        #expect(refuerzo.entry.player.id == s.refuerzo.id)
        #expect(refuerzo.team.team.id == s.cadeteB.id)
        #expect(refuerzo.reportCount == 2)
        #expect(refuerzo.playedCount == 1)
        #expect(refuerzo.convokedWithoutMinutesCount == 1)
        #expect(refuerzo.lastMatch.id == second.id)
        #expect(refuerzo.lastRoundNumber == 2)
    }

    @Test("los de la plantilla no son refuerzos; sin refuerzos, lista vacía (R7.3, P11)")
    func noReinforcements() async throws {
        let (s, _) = try await Self.seed()
        try await A.recorded(s, s.juan, .jugado)
        #expect(try await Self.list(s).execute(actor: A.actor, teamID: s.cadeteA.id, seasonID: s.juan.seasonID).isEmpty)
    }

    @Test("un equipo sin inscribir en la temporada es su 404")
    func teamMustBeRegistered() async throws {
        let (s, _) = try await Self.seed()
        await #expect(throws: ApplicationError.teamNotRegistered(team: "\(s.cadeteB.id)", season: "\(s.juan.seasonID)")) {
            try await Self.list(s).execute(actor: A.actor, teamID: s.cadeteB.id, seasonID: s.juan.seasonID)
        }
    }
}
