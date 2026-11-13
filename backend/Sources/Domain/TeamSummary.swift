/// **Cómo le va a un equipo en una competición** (`D-113`): lo que la portada del
/// backoffice enseña de cada equipo. Una proyección de la clasificación y de los
/// partidos, que se calcula al leer y no se guarda.
public struct TeamSummary: Equatable, Sendable {
    /// El puesto en la última clasificación, o `nil` si todavía no hay ninguna.
    public let position: Int?
    /// La racha de esa misma fila (`D-34`, `D-114`); vacía sin clasificación.
    public let form: [FormEntry]
    /// El último partido jugado de verdad: sin el descanso (`D-105`).
    public let lastMatch: Match?
    /// El de la primera jornada que viene después de lo ya jugado; puede ser el
    /// descanso.
    public let nextMatch: Match?
    /// El puesto del rival del próximo en la última clasificación (`D-113`,
    /// punto 5): un partido sin jugar no trae fila.
    public let nextOpponentPosition: Int?

    public init(
        position: Int?, form: [FormEntry], lastMatch: Match?, nextMatch: Match?, nextOpponentPosition: Int?
    ) {
        self.position = position
        self.form = form
        self.lastMatch = lastMatch
        self.nextMatch = nextMatch
        self.nextOpponentPosition = nextOpponentPosition
    }

    /// Sin nada: la competición sin clasificación ni partidos.
    public static let empty = TeamSummary(
        position: nil, form: [], lastMatch: nil, nextMatch: nil, nextOpponentPosition: nil)

    /// El resumen de `team` con los partidos y las filas de clasificación de su
    /// competición. `roundNumbers`, el número de cada jornada, que ni el partido
    /// ni la fila llevan.
    public static func of(
        _ team: TeamID, matches: [Match], rows: [StandingRow], roundNumbers: [RoundID: Int]
    ) -> TeamSummary {
        // La última clasificación: la de la jornada **más alta** con filas
        // (`D-113`, punto 2), no la que señala `isCurrent`, que es la primera
        // por jugar.
        let latest = rows.compactMap { roundNumbers[$0.roundID] }.max()
        let table = rows.filter { latest != nil && roundNumbers[$0.roundID] == latest }
        let own = table.first { $0.teamID == team }

        let numbered: [(round: Int, match: Match)] = matches.compactMap { match in
            guard match.homeTeamID == team || match.awayTeamID == team,
                  let round = roundNumbers[match.roundID] else { return nil }
            return (round, match)
        }
        // El último jugado de verdad: con marcador, y el descanso no cuenta.
        let last = numbered.filter { $0.match.result != nil && !$0.match.isRestDay }.max { $0.round < $1.round }
        // Lo ya jugado llega hasta la última tabla o el último partido, lo que
        // vaya más lejos; el próximo es el primero sin jugar después, y puede ser
        // el descanso.
        let reached = max(latest ?? 0, last?.round ?? 0)
        let next = numbered.filter { $0.match.result == nil && $0.round > reached }.min { $0.round < $1.round }

        // El puesto del rival, en la última tabla. Si el próximo es el descanso,
        // el rival es el ficticio, que no tiene fila (la federación no lo
        // clasifica), y sale nulo sin mirarlo aparte (lo vio la mutación, R5.5).
        var opponentPosition: Int?
        if let next = next?.match {
            let opponent = next.homeTeamID == team ? next.awayTeamID : next.homeTeamID
            opponentPosition = table.first { $0.teamID == opponent }?.position
        }

        return TeamSummary(
            position: own?.position,
            form: (own == nil ? nil : latest)
                .map { Form.of(team, upTo: $0, matches: matches, roundNumbers: roundNumbers) } ?? [],
            lastMatch: last?.match,
            nextMatch: next?.match,
            nextOpponentPosition: opponentPosition)
    }
}
