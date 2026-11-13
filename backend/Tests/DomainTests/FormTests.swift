import Foundation
import Testing

@testable import Domain

/// Nivel 1 (§8.1): la racha de la clasificación (`D-34`, R4.7), calculada de los
/// partidos.
@Suite("Form · D-34 · la racha, desde Match")
struct FormTests {

    static let epoch = Date(timeIntervalSince1970: 0)
    static let (us, them, others) = (TeamID(raw: UUID()), TeamID(raw: UUID()), TeamID(raw: UUID()))

    /// Siete jornadas; el número de cada una, que el partido no lleva.
    static let rounds = (1...7).map { _ in RoundID(raw: UUID()) }
    static let numbers = Dictionary(uniqueKeysWithValues: rounds.enumerated().map { ($1, $0 + 1) })

    static func match(_ round: Int, _ home: TeamID, _ away: TeamID, _ score: (Int, Int)?) throws -> Match {
        try Match(
            id: MatchID(raw: UUID()), competitionID: CompetitionID(raw: UUID()), roundID: rounds[round - 1],
            kickoff: Kickoff(date: epoch, time: nil), homeTeamID: home, awayTeamID: away,
            result: try score.map { try MatchResult(homeScore: $0.0, awayScore: $0.1) },
            status: score == nil ? .programado : .finalizado, venue: nil, federationMatchID: nil,
            createdAt: epoch, updatedAt: epoch)
    }

    /// Jornadas 1 a 6 jugadas, de local y de visitante, **guardadas
    /// desordenadas**; la 7, sin jugar; y un partido de otros dos equipos.
    static func season() throws -> [Match] {
        [
            try match(3, them, us, (2, 2)),      // empate, de visitante
            try match(1, us, them, (3, 0)),      // victoria
            try match(7, us, them, nil),         // sin jugar
            try match(5, them, us, (0, 1)),      // victoria, de visitante
            try match(2, them, us, (2, 1)),      // derrota, de visitante
            try match(6, us, them, (0, 4)),      // derrota
            try match(4, us, others, (1, 1)),    // empate
            try match(4, them, others, (5, 0)),  // de otros: no cuenta
        ]
    }

    @Test("los últimos cinco jugados, del más reciente al más antiguo, vistos desde el equipo")
    func theLastFive() throws {
        let form = Form.of(Self.us, upTo: 7, matches: try Self.season(), roundNumbers: Self.numbers)
        #expect(form == [
            FormEntry(roundNumber: 6, outcome: .loss),
            FormEntry(roundNumber: 5, outcome: .win),
            FormEntry(roundNumber: 4, outcome: .draw),
            FormEntry(roundNumber: 3, outcome: .draw),
            FormEntry(roundNumber: 2, outcome: .loss),
        ])
    }

    @Test("hasta la jornada pedida: lo de después no cuenta")
    func upToTheRound() throws {
        let form = Form.of(Self.us, upTo: 3, matches: try Self.season(), roundNumbers: Self.numbers)
        #expect(form == [
            FormEntry(roundNumber: 3, outcome: .draw),
            FormEntry(roundNumber: 2, outcome: .loss),
            FormEntry(roundNumber: 1, outcome: .win),
        ])
    }

    @Test("al principio, menos de cinco; sin partidos jugados, ninguna")
    func fewerThanFive() throws {
        #expect(Form.of(Self.us, upTo: 1, matches: try Self.season(), roundNumbers: Self.numbers)
            == [FormEntry(roundNumber: 1, outcome: .win)])
        #expect(Form.of(Self.us, upTo: 7, matches: [try Self.match(7, Self.us, Self.them, nil)],
                        roundNumbers: Self.numbers).isEmpty)
    }

    /// Un descanso, contra el ficticio: sin marcador, con la marca (`D-114`).
    static func rest(_ round: Int, _ team: TeamID) throws -> Match {
        try Match(
            id: MatchID(raw: UUID()), competitionID: CompetitionID(raw: UUID()), roundID: rounds[round - 1],
            kickoff: Kickoff(date: epoch, time: nil), homeTeamID: team, awayTeamID: TeamID(raw: UUID()),
            status: .programado, isRestDay: true, createdAt: epoch, updatedAt: epoch)
    }

    /// **La racha cuenta jornadas** (`D-114`): el descanso de la 4 entra como una
    /// más, en su sitio, y empuja fuera a la 1. Uno de otro equipo, no.
    @Test("el descanso es una jornada más de la racha, y cuenta entre las cinco (D-114)")
    func theRestDayIsAFormEntry() throws {
        let matches = [
            try Self.match(1, Self.us, Self.them, (3, 0)), try Self.match(2, Self.them, Self.us, (2, 1)),
            try Self.match(3, Self.them, Self.us, (2, 2)), try Self.rest(4, Self.us),
            try Self.match(5, Self.them, Self.us, (0, 1)), try Self.match(6, Self.us, Self.them, (0, 4)),
            try Self.rest(5, Self.them),
        ]
        #expect(Form.of(Self.us, upTo: 7, matches: matches, roundNumbers: Self.numbers) == [
            FormEntry(roundNumber: 6, outcome: .loss),
            FormEntry(roundNumber: 5, outcome: .win),
            FormEntry(roundNumber: 4, outcome: .rest),
            FormEntry(roundNumber: 3, outcome: .draw),
            FormEntry(roundNumber: 2, outcome: .loss),
        ])
    }

    /// Un descanso **después** de la jornada pedida tampoco cuenta: es una jornada
    /// que todavía no ha llegado.
    @Test("un descanso posterior a la jornada pedida no cuenta (D-114)")
    func aLaterRestDayDoesNotCount() throws {
        let matches = [try Self.match(1, Self.us, Self.them, (3, 0)), try Self.rest(2, Self.us)]
        #expect(Form.of(Self.us, upTo: 1, matches: matches, roundNumbers: Self.numbers)
            == [FormEntry(roundNumber: 1, outcome: .win)])
    }

    @Test("el rival ve el mismo partido al revés")
    func theOtherSide() throws {
        let form = Form.of(Self.them, upTo: 1, matches: try Self.season(), roundNumbers: Self.numbers)
        #expect(form == [FormEntry(roundNumber: 1, outcome: .loss)])
    }
}
