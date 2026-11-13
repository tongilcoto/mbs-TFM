import Foundation
import Testing

@testable import Domain

/// Nivel 1 (§8.1): el resumen de un equipo en su competición (`D-113`), con el
/// descanso (`D-105`, `D-114`).
@Suite("TeamSummary · D-113 · posición, racha, último y próximo partido")
struct TeamSummaryTests {

    static let epoch = Date(timeIntervalSince1970: 0)
    static let competition = CompetitionID(raw: UUID())
    static let (us, them, others, ghost) = (
        TeamID(raw: UUID()), TeamID(raw: UUID()), TeamID(raw: UUID()), TeamID(raw: UUID()))

    /// Seis jornadas; el número de cada una, que el partido no lleva.
    static let rounds = (1...6).map { _ in RoundID(raw: UUID()) }
    static let numbers = Dictionary(uniqueKeysWithValues: rounds.enumerated().map { ($1, $0 + 1) })

    static func match(_ round: Int, _ home: TeamID, _ away: TeamID, _ score: (Int, Int)? = nil) throws -> Match {
        try Match(
            id: MatchID(raw: UUID()), competitionID: competition, roundID: rounds[round - 1],
            kickoff: Kickoff(date: epoch), homeTeamID: home, awayTeamID: away,
            result: try score.map { try MatchResult(homeScore: $0.0, awayScore: $0.1) },
            status: score == nil ? .programado : .finalizado, createdAt: epoch, updatedAt: epoch)
    }

    static func rest(_ round: Int, _ team: TeamID) throws -> Match {
        try Match(
            id: MatchID(raw: UUID()), competitionID: competition, roundID: rounds[round - 1],
            kickoff: Kickoff(date: epoch), homeTeamID: team, awayTeamID: ghost,
            status: .programado, isRestDay: true, createdAt: epoch, updatedAt: epoch)
    }

    static func row(_ round: Int, _ team: TeamID, _ position: Int, previous: Int? = nil) throws -> StandingRow {
        try StandingRow(
            id: StandingRowID(raw: UUID()), competitionID: competition, roundID: rounds[round - 1], teamID: team,
            position: position, previousPosition: previous, played: round, won: 0, drawn: 0, lost: round,
            goalsFor: 0, goalsAgainst: 0, points: 0, createdAt: epoch, updatedAt: epoch)
    }

    /// Jornadas 1 a 3 jugadas, con su tabla; la 4 y la 5 por jugar. Los
    /// partidos, **guardados desordenados**.
    static func season() throws -> (matches: [Match], rows: [StandingRow]) {
        let matches = [
            try match(2, them, us, (2, 1)), try match(5, others, us), try match(1, us, them, (3, 0)),
            try match(4, us, others), try match(3, us, others, (1, 1)), try match(3, them, others, (0, 2)),
        ]
        var rows: [StandingRow] = []
        for (round, order) in [(1, [us, others, them]), (2, [them, us, others]), (3, [others, us, them])] {
            for (index, team) in order.enumerated() { rows.append(try row(round, team, index + 1)) }
        }
        return (matches, rows)
    }

    @Test("la posición y la racha son las de la última clasificación")
    func positionAndFormFromTheLatestTable() throws {
        let (matches, rows) = try Self.season()
        let summary = TeamSummary.of(Self.us, matches: matches, rows: rows, roundNumbers: Self.numbers)
        #expect(summary.position == 2)
        #expect(summary.form == [
            FormEntry(roundNumber: 3, outcome: .draw),
            FormEntry(roundNumber: 2, outcome: .loss),
            FormEntry(roundNumber: 1, outcome: .win),
        ])
    }

    @Test("el último partido es el de la jornada jugada más alta; el próximo, el de la siguiente")
    func lastAndNext() throws {
        let (matches, rows) = try Self.season()
        let summary = TeamSummary.of(Self.us, matches: matches, rows: rows, roundNumbers: Self.numbers)
        #expect(summary.lastMatch.map { Self.numbers[$0.roundID] } == 3)
        #expect(summary.nextMatch.map { Self.numbers[$0.roundID] } == 4)
    }

    @Test("el puesto del rival del próximo es el suyo en la última clasificación")
    func theNextOpponentPosition() throws {
        let (matches, rows) = try Self.season()
        let summary = TeamSummary.of(Self.us, matches: matches, rows: rows, roundNumbers: Self.numbers)
        #expect(summary.nextOpponentPosition == 1)
    }

    @Test("sin nada jugado: ni puesto ni racha ni último; el próximo, el de la primera jornada")
    func nothingPlayed() throws {
        let matches = [try Self.match(2, Self.them, Self.us), try Self.match(1, Self.us, Self.them)]
        let summary = TeamSummary.of(Self.us, matches: matches, rows: [], roundNumbers: Self.numbers)
        #expect(summary.position == nil)
        #expect(summary.form.isEmpty)
        #expect(summary.lastMatch == nil)
        #expect(summary.nextMatch.map { Self.numbers[$0.roundID] } == 1)
        #expect(summary.nextOpponentPosition == nil)
    }

    @Test("con todo jugado, no hay próximo")
    func everythingPlayed() throws {
        let matches = [try Self.match(1, Self.us, Self.them, (1, 0)), try Self.match(2, Self.them, Self.us, (0, 0))]
        let rows = [try Self.row(1, Self.us, 1), try Self.row(2, Self.us, 1)]
        let summary = TeamSummary.of(Self.us, matches: matches, rows: rows, roundNumbers: Self.numbers)
        #expect(summary.lastMatch.map { Self.numbers[$0.roundID] } == 2)
        #expect(summary.nextMatch == nil)
    }

    /// **El descanso no es «último partido»** (`D-113`, punto 6): si el equipo
    /// descansó en la última jornada jugada, el último es el de antes. Y la
    /// racha lo cuenta (`D-114`).
    @Test("si descansó en la última jornada jugada, el último es el de antes, y la racha lo cuenta")
    func restInTheLastPlayedRound() throws {
        let matches = [
            try Self.match(1, Self.us, Self.them, (3, 0)), try Self.match(2, Self.them, Self.us, (2, 1)),
            try Self.rest(3, Self.us), try Self.match(4, Self.us, Self.them),
        ]
        let rows = try [1, 2, 3].map { try Self.row($0, Self.us, 2) }
        let summary = TeamSummary.of(Self.us, matches: matches, rows: rows, roundNumbers: Self.numbers)
        #expect(summary.lastMatch.map { Self.numbers[$0.roundID] } == 2)
        #expect(summary.nextMatch.map { Self.numbers[$0.roundID] } == 4)
        #expect(summary.form.first == FormEntry(roundNumber: 3, outcome: .rest))
    }

    /// **Si descansa en la próxima jornada, el próximo es su descanso**, para
    /// que el cliente diga «Descansa»; y sin puesto del rival.
    @Test("si descansa en la próxima jornada, el próximo es el descanso, sin puesto del rival")
    func restInTheNextRound() throws {
        let matches = [try Self.match(1, Self.us, Self.them, (3, 0)), try Self.rest(2, Self.us),
                       try Self.match(3, Self.them, Self.us)]
        let rows = [try Self.row(1, Self.us, 1), try Self.row(1, Self.them, 2)]
        let summary = TeamSummary.of(Self.us, matches: matches, rows: rows, roundNumbers: Self.numbers)
        #expect(summary.nextMatch?.isRestDay == true)
        #expect(summary.nextMatch.map { Self.numbers[$0.roundID] } == 2)
        #expect(summary.nextOpponentPosition == nil)
    }

    /// **Sin clasificación, lo jugado lo dice el último partido**: un descanso
    /// que ya pasó (la jornada 2, entre la 1 y la 3 jugadas) no es el próximo.
    /// Pasa con una federación que no publica la tabla, o antes de ingerirla.
    @Test("sin clasificación, un descanso que ya pasó no es el próximo partido")
    func withoutTableAPastRestIsNotNext() throws {
        let matches = [
            try Self.match(1, Self.us, Self.them, (3, 0)), try Self.rest(2, Self.us),
            try Self.match(3, Self.them, Self.us, (1, 1)), try Self.match(4, Self.us, Self.them),
        ]
        let summary = TeamSummary.of(Self.us, matches: matches, rows: [], roundNumbers: Self.numbers)
        #expect(summary.lastMatch.map { Self.numbers[$0.roundID] } == 3)
        #expect(summary.nextMatch.map { Self.numbers[$0.roundID] } == 4)
    }

    /// La clasificación de otra jornada **más antigua** no gana a la última,
    /// aunque llegue después en la lista: manda el número de la jornada.
    @Test("la última clasificación es la de la jornada más alta, no la última de la lista")
    func theLatestTableIsTheHighestRound() throws {
        let rows = [try Self.row(3, Self.us, 4), try Self.row(1, Self.us, 1)]
        let summary = TeamSummary.of(Self.us, matches: [], rows: rows, roundNumbers: Self.numbers)
        #expect(summary.position == 4)
    }
}
