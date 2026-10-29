import Domain
import Foundation
import Testing
@testable import Application

/// Nivel 2 (§8.1): `ListMatches` con los repositorios en memoria (R4.8). Lo que
/// decide el caso de uso: los tres ámbitos y que se sumen, la temporada y el
/// estado, el orden de calendario con las horas sin fijar al final del día, la
/// página y su total, el número de jornada, los nombres de cada equipo, **la fila
/// de la clasificación de cada lado** (`D-112`) y los 404 de cada ámbito.
@Suite("ListMatches · R4.8 · partidos, siempre dentro de un ámbito")
struct ListMatchesTests {

    static let epoch = Date(timeIntervalSince1970: 0)
    static let actor = ListSeasonRegistrationsTests.actor
    static let club = ListSeasonRegistrationsTests.club

    static func day(_ text: String) -> Date { try! Date("\(text)T00:00:00Z", strategy: .iso8601) }

    struct Seeded {
        let store: IngestionStore
        let season: SeasonID, otherSeason: SeasonID
        let liga: CompetitionID, otherLiga: CompetitionID
        let rounds: [Round]
        let own: Team, rival: Team, third: Team
        let rivalClub: OpponentClub
        /// Los de la liga, por orden de calendario: j1 (sáb 18:00), j1 (sáb, sin
        /// hora), j2 (sáb 10:00), j2 (dom), j3 (sin jugar).
        let ordered: [Match]
        /// El del propio en la otra temporada.
        let elsewhere: Match
    }

    /// Una liga de 2025/26 con tres jornadas (la 1 y la 2 jugadas, con tabla) y
    /// otra de 2024/25 con un partido del propio. Los partidos se guardan
    /// desordenados.
    static func seed() async throws -> Seeded {
        let (season, otherSeason) = (SeasonID(raw: UUID()), SeasonID(raw: UUID()))
        let (liga, otherLiga) = (CompetitionID(raw: UUID()), CompetitionID(raw: UUID()))
        func competition(_ id: CompetitionID, _ season: SeasonID, group: String) throws -> Competition {
            try Competition(
                id: id, seasonID: season, modality: .futbol11, gender: .masculino, federationCompetitionID: "1",
                federationGroupID: group, ageCategory: .cadete, divisionLabel: "PRIMERA CADETE", groupLabel: "Grupo 1",
                createdAt: epoch, updatedAt: epoch)
        }
        let seasons = try [(season, "2025/26"), (otherSeason, "2024/25")].map {
            try Season(id: $0.0, label: try SeasonLabel($0.1), federationSeasonID: nil, createdAt: epoch, updatedAt: epoch)
        }
        let rivalClub = try OpponentClub(
            id: OpponentClubID(raw: UUID()), name: "C.D. GALAPAGAR", shortName: "Galapagar",
            slug: try Slug("c-d-galapagar"), createdAt: epoch, updatedAt: epoch)
        let own = try Team(
            id: TeamID(raw: UUID()), category: .cadete, letter: "A", gender: .masculino, modality: .futbol11,
            createdAt: epoch, updatedAt: epoch)
        let rival = try Team(
            id: TeamID(raw: UUID()), opponentClubID: rivalClub.id, seasonID: season, category: .cadete, letter: "B",
            gender: .masculino, modality: .futbol11, createdAt: epoch, updatedAt: epoch)
        let third = try Team(
            id: TeamID(raw: UUID()), opponentClubID: rivalClub.id, seasonID: season, category: .cadete, letter: "C",
            gender: .masculino, modality: .futbol11, createdAt: epoch, updatedAt: epoch)
        let rounds = try [("2025-10-04", "2025-10-05"), ("2025-10-11", "2025-10-12"), ("2025-10-18", "2025-10-18")]
            .enumerated().map { index, span in
                try Round(
                    id: RoundID(raw: UUID()), competitionID: liga, number: index + 1, startDate: day(span.0),
                    endDate: day(span.1), createdAt: epoch, updatedAt: epoch)
            }
        let otherRound = try Round(
            id: RoundID(raw: UUID()), competitionID: otherLiga, number: 1, startDate: day("2024-10-05"),
            endDate: day("2024-10-05"), createdAt: epoch, updatedAt: epoch)
        func match(
            _ round: Round, _ date: String, _ time: (Int, Int)?, _ home: Team, _ away: Team, _ score: (Int, Int)?
        ) throws -> Match {
            try Match(
                id: MatchID(raw: UUID()), competitionID: round.competitionID, roundID: round.id,
                kickoff: Kickoff(date: day(date), time: time.flatMap { WallClockTime(hour: $0.0, minute: $0.1) }),
                homeTeamID: home.id, awayTeamID: away.id,
                result: try score.map { try MatchResult(homeScore: $0.0, awayScore: $0.1) },
                status: score == nil ? .programado : .finalizado, createdAt: epoch, updatedAt: epoch)
        }
        let ordered = [
            try match(rounds[0], "2025-10-04", (18, 0), own, rival, (2, 0)),
            try match(rounds[0], "2025-10-04", nil, third, rival, (1, 1)),
            try match(rounds[1], "2025-10-11", (10, 0), rival, own, (3, 1)),
            try match(rounds[1], "2025-10-12", (12, 0), own, third, (0, 0)),
            try match(rounds[2], "2025-10-18", nil, third, own, nil),
        ]
        let elsewhere = try match(otherRound, "2024-10-05", (11, 0), own, rival, (1, 0))
        func row(_ round: Round, _ team: Team, _ position: Int) throws -> StandingRow {
            try StandingRow(
                id: StandingRowID(raw: UUID()), competitionID: liga, roundID: round.id, teamID: team.id,
                position: position, played: round.number, won: 0, drawn: 0, lost: round.number, goalsFor: 0,
                goalsAgainst: 0, points: 10 * round.number + position, createdAt: epoch, updatedAt: epoch)
        }
        let store = IngestionStore()
        await store.seed(club: club)
        await store.seed(
            seasons: seasons,
            competitions: [try competition(liga, season, group: "2"), try competition(otherLiga, otherSeason, group: "3")],
            rounds: rounds + [otherRound], opponentClubs: [rivalClub], teams: [own, rival, third],
            matches: [ordered[3], elsewhere, ordered[0], ordered[4], ordered[2], ordered[1]],
            standingRows: [
                try row(rounds[0], own, 1), try row(rounds[0], third, 2), try row(rounds[0], rival, 3),
                try row(rounds[1], rival, 1), try row(rounds[1], own, 2), try row(rounds[1], third, 3),
            ])
        return Seeded(
            store: store, season: season, otherSeason: otherSeason, liga: liga, otherLiga: otherLiga, rounds: rounds,
            own: own, rival: rival, third: third, rivalClub: rivalClub, ordered: ordered, elsewhere: elsewhere)
    }

    static func run(_ seeded: Seeded, _ query: ListMatches.Query) async throws -> ListMatches.Page {
        let store = seeded.store
        return try await ListMatches(
            clubs: FakeClubRepository(store: store), seasons: FakeSeasonRepository(store: store),
            competitions: FakeCompetitionRepository(store: store), rounds: FakeRoundRepository(store: store),
            matches: FakeMatchRepository(store: store), standingRows: FakeStandingRowRepository(store: store),
            teams: FakeTeamRepository(store: store), opponentClubs: FakeOpponentClubRepository(store: store)
        ).execute(actor: actor, query: query)
    }

    // ── Los ámbitos ─────────────────────────────────────────────────────────

    @Test("por competición: todo su calendario, en orden, con la hora sin fijar al final del día")
    func byCompetitionInCalendarOrder() async throws {
        let seeded = try await Self.seed()
        let page = try await Self.run(seeded, .init(competitionID: seeded.liga))
        #expect(page.lines.map(\.match.id) == seeded.ordered.map(\.id))
        #expect(page.total == 5)
    }

    @Test("por equipo y temporada: los suyos, de local y de visitante, de esa temporada")
    func byTeamAndSeason() async throws {
        let seeded = try await Self.seed()
        let page = try await Self.run(seeded, .init(teamID: seeded.own.id, seasonID: seeded.season))
        #expect(page.lines.map(\.match.id) == [0, 2, 3, 4].map { seeded.ordered[$0].id })
    }

    @Test("por equipo sin temporada: también los de otras temporadas")
    func byTeamAcrossSeasons() async throws {
        let seeded = try await Self.seed()
        let page = try await Self.run(seeded, .init(teamID: seeded.own.id))
        #expect(page.lines.map(\.match.id) == [seeded.elsewhere.id] + [0, 2, 3, 4].map { seeded.ordered[$0].id })
    }

    @Test("por jornada: los de esa jornada")
    func byRound() async throws {
        let seeded = try await Self.seed()
        let page = try await Self.run(seeded, .init(roundID: seeded.rounds[1].id))
        #expect(page.lines.map(\.match.id) == [2, 3].map { seeded.ordered[$0].id })
    }

    @Test("los ámbitos se suman: el equipo en una jornada")
    func scopesCombine() async throws {
        let seeded = try await Self.seed()
        let page = try await Self.run(seeded, .init(roundID: seeded.rounds[0].id, teamID: seeded.third.id))
        #expect(page.lines.map(\.match.id) == [seeded.ordered[1].id])
    }

    // ── Filtros, orden y página ─────────────────────────────────────────────

    @Test("por estado: solo los programados")
    func byStatus() async throws {
        let seeded = try await Self.seed()
        let page = try await Self.run(seeded, .init(competitionID: seeded.liga, status: .programado))
        #expect(page.lines.map(\.match.id) == [seeded.ordered[4].id])
    }

    @Test("del más reciente al más antiguo, con order=desc")
    func newestFirst() async throws {
        let seeded = try await Self.seed()
        let page = try await Self.run(seeded, .init(competitionID: seeded.liga, newestFirst: true))
        #expect(page.lines.map(\.match.id) == seeded.ordered.reversed().map(\.id))
    }

    @Test("la página pedida, con el total de todos")
    func paginates() async throws {
        let seeded = try await Self.seed()
        let page = try await Self.run(seeded, .init(competitionID: seeded.liga, page: 2, perPage: 2))
        #expect(page.lines.map(\.match.id) == [2, 3].map { seeded.ordered[$0].id })
        #expect(page.total == 5)
        #expect((page.page, page.perPage) == (2, 2))
        let beyond = try await Self.run(seeded, .init(competitionID: seeded.liga, page: 4, perPage: 2))
        #expect(beyond.lines.isEmpty)
        #expect(beyond.total == 5)
    }

    // ── Lo que lleva cada partido ───────────────────────────────────────────

    @Test("cada partido con el número de su jornada")
    func withRoundNumber() async throws {
        let seeded = try await Self.seed()
        let page = try await Self.run(seeded, .init(competitionID: seeded.liga))
        #expect(page.lines.map(\.roundNumber) == [1, 1, 2, 2, 3])
    }

    @Test("cada lado con los nombres de su club, el propio o el rival")
    func eachSideWithItsClub() async throws {
        let seeded = try await Self.seed()
        let line = try #require(try await Self.run(seeded, .init(roundID: seeded.rounds[1].id)).lines.first)
        #expect(line.home.team == LabeledTeam(team: seeded.rival, clubName: "C.D. GALAPAGAR", clubShortName: "Galapagar"))
        #expect(line.away.team == LabeledTeam(team: seeded.own, clubName: Self.club.name, clubShortName: Self.club.shortName))
    }

    /// `D-112`: la fila de **esa** jornada, no la de otra; nada si no tiene tabla.
    @Test("cada lado con su fila de la clasificación de esa jornada, o nada si no la tiene")
    func eachSideWithItsStanding() async throws {
        let seeded = try await Self.seed()
        let lines = try await Self.run(seeded, .init(competitionID: seeded.liga)).lines
        try #require(lines.count == 5)
        #expect(lines[0].home.standing?.points == 11)   // propio, tras la 1: 1º
        #expect(lines[0].away.standing?.points == 13)   // rival, tras la 1: 3º
        #expect(lines[2].home.standing?.points == 21)   // rival, tras la 2: 1º
        #expect(lines[2].away.standing?.points == 22)   // propio, tras la 2: 2º
        #expect(lines[4].home.standing == nil)          // la 3, sin tabla
        #expect(lines[4].away.standing == nil)
    }

    // ── Los 404 de cada ámbito ──────────────────────────────────────────────

    @Test("un ámbito que no existe es su 404")
    func unknownScopes() async throws {
        let seeded = try await Self.seed()
        let (round, competition, team, season) =
            (RoundID(raw: UUID()), CompetitionID(raw: UUID()), TeamID(raw: UUID()), SeasonID(raw: UUID()))
        await #expect(throws: ApplicationError.roundNotFound(id: "\(round)")) {
            _ = try await Self.run(seeded, .init(roundID: round))
        }
        await #expect(throws: ApplicationError.competitionNotFound(id: "\(competition)")) {
            _ = try await Self.run(seeded, .init(competitionID: competition))
        }
        await #expect(throws: ApplicationError.teamNotFound(id: "\(team)")) {
            _ = try await Self.run(seeded, .init(teamID: team))
        }
        await #expect(throws: ApplicationError.unknownSeason(id: "\(season)")) {
            _ = try await Self.run(seeded, .init(teamID: seeded.own.id, seasonID: season))
        }
    }
}
