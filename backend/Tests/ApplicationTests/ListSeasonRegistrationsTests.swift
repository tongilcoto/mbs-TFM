import Domain
import Foundation
import Testing
@testable import Application

/// Nivel 2 (§8.1): `ListSeasonRegistrations` con los repositorios en memoria
/// (`D-102`; Plan R1, R1.9). Las consultas las prueba el nivel 3; aquí se prueba
/// lo que decide el caso de uso: **un elemento por equipo** con sus competiciones
/// dentro, la fila de junio con la lista vacía, el orden, y el 404 de una
/// temporada que no existe.
@Suite("ListSeasonRegistrations · D-102 · el equipo en una temporada, leído")
struct ListSeasonRegistrationsTests {

    static let epoch = Date(timeIntervalSince1970: 0)

    static func team(_ category: TeamCategory, _ letter: String?) throws -> Team {
        try Team(
            id: TeamID(raw: UUID()), opponentClubID: nil, category: category, letter: letter,
            gender: .masculino, modality: .futbol11, createdAt: epoch, updatedAt: epoch)
    }

    static func registration(
        _ team: Team, _ season: SeasonID, _ competition: CompetitionID? = nil,
        code: String? = nil, at seconds: TimeInterval = 0
    ) throws -> TeamRegistration {
        try TeamRegistration(
            id: TeamRegistrationID(raw: UUID()), team: team, seasonID: season,
            competitionID: competition, federationTeamID: code,
            createdAt: Date(timeIntervalSince1970: seconds), updatedAt: epoch)
    }

    static let club = try! Club(
        id: .init(raw: UUID()), name: "Celtic Castilla Club de Fútbol", shortName: "Celtic Castilla",
        slug: try! Slug("celtic-castilla"), federation: .rffm, createdAt: epoch, updatedAt: epoch)
    static let actor = ActorContext(clubSlug: try! Slug("celtic-castilla"))

    static func useCase(_ store: IngestionStore) -> ListSeasonRegistrations {
        ListSeasonRegistrations(
            clubs: FakeClubRepository(store: store), seasons: FakeSeasonRepository(store: store),
            teams: FakeTeamRepository(store: store),
            registrations: FakeTeamRegistrationRepository(store: store),
            summaries: CompetitionSummaries(
                rounds: FakeRoundRepository(store: store), matches: FakeMatchRepository(store: store),
                standingRows: FakeStandingRowRepository(store: store), teams: FakeTeamRepository(store: store),
                opponentClubs: FakeOpponentClubRepository(store: store)))
    }

    /// Cuatro equipos **guardados desordenados**: el Cadete B con liga y copa, el
    /// Alevín A sin competición (junio), el Cadete A y el Infantil, sin letra.
    /// Y una inscripción del Cadete A en **otra** temporada, que no sale.
    @Test("un elemento por equipo, con sus competiciones; ordenados por categoría y letra")
    func oneEntryPerTeamInOrder() async throws {
        let season = try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel("2026/27"), federationSeasonID: "22",
            createdAt: Self.epoch, updatedAt: Self.epoch)
        let other = SeasonID(raw: UUID())
        let (liga, copa, infantilLiga, cadeteALiga) =
            (CompetitionID(raw: UUID()), CompetitionID(raw: UUID()),
             CompetitionID(raw: UUID()), CompetitionID(raw: UUID()))
        let cadeteB = try Self.team(.cadete, "B")
        let alevinA = try Self.team(.alevin, "A")
        let cadeteA = try Self.team(.cadete, "A")
        let infantil = try Self.team(.infantil, nil)

        let store = IngestionStore()
        await store.seed(club: Self.club)
        await store.seed(seasons: [season], teams: [cadeteB, alevinA, cadeteA, infantil])
        await store.seed(teamRegistrations: [
            try Self.registration(cadeteB, season.id, copa, code: "900", at: 20),
            try Self.registration(alevinA, season.id),
            try Self.registration(cadeteB, season.id, liga, code: "821", at: 10),
            try Self.registration(infantil, season.id, infantilLiga, code: "333"),
            try Self.registration(cadeteA, season.id, cadeteALiga, code: "777"),
            try Self.registration(cadeteA, other, CompetitionID(raw: UUID()), code: "666"),
        ])

        let result = try await Self.useCase(store).execute(actor: Self.actor, seasonID: season.id)

        #expect(result.club == Self.club)
        #expect(result.entries == [
            SeasonRegistration(team: alevinA, seasonID: season.id, competitions: []),
            SeasonRegistration(team: infantil, seasonID: season.id, competitions: [
                RegisteredCompetition(competitionID: infantilLiga, federationTeamID: "333"),
            ]),
            SeasonRegistration(team: cadeteA, seasonID: season.id, competitions: [
                RegisteredCompetition(competitionID: cadeteALiga, federationTeamID: "777"),
            ]),
            // La liga antes que la copa: en el orden en que se inscribieron.
            SeasonRegistration(team: cadeteB, seasonID: season.id, competitions: [
                RegisteredCompetition(competitionID: liga, federationTeamID: "821"),
                RegisteredCompetition(competitionID: copa, federationTeamID: "900"),
            ]),
        ])
    }

    @Test("una temporada sin inscripciones da la lista vacía, no un error")
    func aSeasonWithoutRegistrationsIsEmpty() async throws {
        let season = try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel("2026/27"), federationSeasonID: "22",
            createdAt: Self.epoch, updatedAt: Self.epoch)
        let store = IngestionStore()
        await store.seed(club: Self.club)
        await store.seed(seasons: [season])

        let result = try await Self.useCase(store).execute(actor: Self.actor, seasonID: season.id)

        #expect(result.entries.isEmpty)
    }

    /// **El resumen de cada competición** (`D-113`), montado por el caso de uso: la
    /// regla es del dominio (`TeamSummary`), y aquí se prueba que se leen los
    /// partidos y la clasificación de **esa** competición, y que el último y el
    /// próximo partido llevan cada lado con su club y su fila de esa jornada.
    /// El Cadete A contra el Galapagar B: jornada 1 jugada (2-1), con tabla; la 2,
    /// por jugar. Y otra competición con sus propios partidos, que no se mezcla.
    @Test("cada competición trae su resumen: puesto, racha, y último y próximo con sus lados (D-113)")
    func eachCompetitionCarriesItsSummary() async throws {
        let season = try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel("2026/27"), federationSeasonID: "22",
            createdAt: Self.epoch, updatedAt: Self.epoch)
        let (liga, otra) = (CompetitionID(raw: UUID()), CompetitionID(raw: UUID()))
        let rounds = try (1...2).map {
            try Round(id: RoundID(raw: UUID()), competitionID: liga, number: $0, startDate: Self.epoch,
                      endDate: Self.epoch, createdAt: Self.epoch, updatedAt: Self.epoch)
        }
        let otherRound = try Round(id: RoundID(raw: UUID()), competitionID: otra, number: 1, startDate: Self.epoch,
                                   endDate: Self.epoch, createdAt: Self.epoch, updatedAt: Self.epoch)
        let cadeteA = try Self.team(.cadete, "A")
        let galapagarClub = try OpponentClub(
            id: OpponentClubID(raw: UUID()), name: "C.D. GALAPAGAR", shortName: "Galapagar",
            slug: try Slug("c-d-galapagar"), createdAt: Self.epoch, updatedAt: Self.epoch)
        let galapagar = try Team(
            id: TeamID(raw: UUID()), opponentClubID: galapagarClub.id, seasonID: season.id, category: .cadete,
            letter: "B", gender: .masculino, modality: .futbol11, createdAt: Self.epoch, updatedAt: Self.epoch)
        func match(_ round: Round, _ home: Team, _ away: Team, _ score: (Int, Int)?) throws -> Match {
            try Match(
                id: MatchID(raw: UUID()), competitionID: round.competitionID, roundID: round.id,
                kickoff: Kickoff(date: Self.epoch), homeTeamID: home.id, awayTeamID: away.id,
                result: try score.map { try MatchResult(homeScore: $0.0, awayScore: $0.1) },
                status: score == nil ? .programado : .finalizado, createdAt: Self.epoch, updatedAt: Self.epoch)
        }
        func row(_ round: Round, _ team: Team, _ position: Int, _ previous: Int?) throws -> StandingRow {
            try StandingRow(
                id: StandingRowID(raw: UUID()), competitionID: round.competitionID, roundID: round.id,
                teamID: team.id, position: position, previousPosition: previous, played: 1, won: 0, drawn: 0,
                lost: 0, goalsFor: 0, goalsAgainst: 0, points: 0, createdAt: Self.epoch, updatedAt: Self.epoch)
        }
        let played = try match(rounds[0], cadeteA, galapagar, (2, 1))
        let next = try match(rounds[1], galapagar, cadeteA, nil)

        let store = IngestionStore()
        await store.seed(club: Self.club)
        await store.seed(
            seasons: [season], rounds: rounds + [otherRound], opponentClubs: [galapagarClub],
            teams: [cadeteA, galapagar],
            matches: [next, played, try match(otherRound, galapagar, cadeteA, (5, 0))],
            standingRows: [try row(rounds[0], cadeteA, 1, 4), try row(rounds[0], galapagar, 2, 3),
                           try row(otherRound, cadeteA, 9, nil)])
        await store.seed(teamRegistrations: [try Self.registration(cadeteA, season.id, liga, code: "777")])

        let result = try await Self.useCase(store).execute(actor: Self.actor, seasonID: season.id)

        let summary = try #require(result.entries.first?.competitions.first).summary
        #expect(summary.position == 1)
        #expect(summary.form == [FormEntry(roundNumber: 1, outcome: .win)])
        #expect(summary.nextOpponentPosition == 2)
        let last = try #require(summary.lastMatch)
        #expect(last.match == played)
        #expect(last.roundNumber == 1)
        #expect(last.home.team.clubName == Self.club.name)
        #expect(last.away.team.clubName == "C.D. GALAPAGAR")
        #expect(last.home.standing?.previousPosition == 4)
        #expect(last.away.standing?.previousPosition == 3)
        let upcoming = try #require(summary.nextMatch)
        #expect(upcoming.match == next)
        #expect(upcoming.roundNumber == 2)
        #expect(upcoming.home.team.team == galapagar)
        #expect(upcoming.home.standing == nil)
    }

    /// **La última tabla puede ser de una jornada posterior al último partido**:
    /// el Cadete A juega la 1 y descansa en la 2, que ya tiene tabla. Los lados
    /// del último partido llevan la fila de **su** jornada, la 1, no la de la
    /// última tabla.
    @Test("los lados del último partido llevan la fila de su jornada, aunque la última tabla sea de otra")
    func theLastMatchSidesUseTheirOwnRound() async throws {
        let season = try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel("2026/27"), federationSeasonID: "22",
            createdAt: Self.epoch, updatedAt: Self.epoch)
        let liga = CompetitionID(raw: UUID())
        let rounds = try (1...2).map {
            try Round(id: RoundID(raw: UUID()), competitionID: liga, number: $0, startDate: Self.epoch,
                      endDate: Self.epoch, createdAt: Self.epoch, updatedAt: Self.epoch)
        }
        let (cadeteA, rival, ghost) = (try Self.team(.cadete, "A"), try Self.team(.cadete, "B"), try Self.team(.cadete, "C"))
        let played = try Match(
            id: MatchID(raw: UUID()), competitionID: liga, roundID: rounds[0].id, kickoff: Kickoff(date: Self.epoch),
            homeTeamID: cadeteA.id, awayTeamID: rival.id, result: try MatchResult(homeScore: 1, awayScore: 0),
            status: .finalizado, createdAt: Self.epoch, updatedAt: Self.epoch)
        let rest = try Match(
            id: MatchID(raw: UUID()), competitionID: liga, roundID: rounds[1].id, kickoff: Kickoff(date: Self.epoch),
            homeTeamID: cadeteA.id, awayTeamID: ghost.id, status: .programado, isRestDay: true,
            createdAt: Self.epoch, updatedAt: Self.epoch)
        func row(_ round: Round, _ team: Team, _ position: Int) throws -> StandingRow {
            try StandingRow(
                id: StandingRowID(raw: UUID()), competitionID: liga, roundID: round.id, teamID: team.id,
                position: position, played: 1, won: 0, drawn: 0, lost: 0, goalsFor: 0, goalsAgainst: 0, points: 0,
                createdAt: Self.epoch, updatedAt: Self.epoch)
        }
        let store = IngestionStore()
        await store.seed(club: Self.club)
        await store.seed(
            seasons: [season], rounds: rounds, teams: [cadeteA, rival, ghost], matches: [played, rest],
            standingRows: [try row(rounds[0], cadeteA, 1), try row(rounds[0], rival, 2),
                           try row(rounds[1], cadeteA, 2), try row(rounds[1], rival, 1)])
        await store.seed(teamRegistrations: [try Self.registration(cadeteA, season.id, liga, code: "777")])

        let result = try await Self.useCase(store).execute(actor: Self.actor, seasonID: season.id)

        let summary = try #require(result.entries.first?.competitions.first).summary
        #expect(summary.position == 2)
        let last = try #require(summary.lastMatch)
        #expect(last.match == played)
        #expect(last.home.standing?.position == 1)
        #expect(last.away.standing?.position == 2)
    }

    /// El id lo puso quien llama: es un dato suyo que no existe, **404**.
    @Test("una temporada que no existe es unknownSeason (404)")
    func anUnknownSeasonIsNotFound() async throws {
        let store = IngestionStore()
        await store.seed(club: Self.club)
        let missing = SeasonID(raw: UUID())

        await #expect(throws: ApplicationError.unknownSeason(id: "\(missing)")) {
            try await Self.useCase(store).execute(actor: Self.actor, seasonID: missing)
        }
    }
}
