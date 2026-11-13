/// **El resultado de un partido visto desde uno de sus equipos** (R4.7): la
/// columna RACHA de la clasificación (`D-34`). No confundir con `MatchStatus`,
/// que es del partido y vale lo mismo para los dos; ni con `MatchOutcome`, que es
/// el desenlace de la cadena de emparejamiento de la ingesta.
public enum TeamOutcome: Equatable, Sendable {
    case win, draw, loss
    /// La jornada en la que el equipo descansa, en un grupo impar (`D-114`).
    case rest
}

/// Un partido de la racha: su jornada y cómo le fue al equipo.
public struct FormEntry: Equatable, Sendable {
    public let roundNumber: Int
    public let outcome: TeamOutcome

    public init(roundNumber: Int, outcome: TeamOutcome) {
        self.roundNumber = roundNumber
        self.outcome = outcome
    }
}

public enum Form {
    /// **La racha de un equipo hasta una jornada** (`D-34`): sus últimas `limit`
    /// jornadas **jugadas**, del más reciente al más antiguo, con la de descanso
    /// como una más (`D-114`).
    /// Se deriva de `Match`, no de restar clasificaciones consecutivas, que en
    /// un alta a mitad de temporada no están (`D-33`).
    ///
    /// - `matches`: los partidos de la competición; los de otros equipos y los
    ///   sin marcador no cuentan, salvo el descanso del equipo.
    /// - `roundNumbers`: el número de cada jornada, que el partido no lleva.
    public static func of(
        _ team: TeamID, upTo roundNumber: Int, matches: [Match], roundNumbers: [RoundID: Int], limit: Int = 5
    ) -> [FormEntry] {
        let played: [(round: Int, entry: FormEntry)] = matches.compactMap { match in
            guard let round = roundNumbers[match.roundID], round <= roundNumber else { return nil }
            // La racha cuenta jornadas (`D-114`): el descanso del equipo es una más.
            if match.isRestDay {
                guard match.homeTeamID == team || match.awayTeamID == team else { return nil }
                return (round, FormEntry(roundNumber: round, outcome: .rest))
            }
            guard let result = match.result else { return nil }
            let (scored, conceded): (Int, Int)
            switch team {
            case match.homeTeamID: (scored, conceded) = (result.homeScore, result.awayScore)
            case match.awayTeamID: (scored, conceded) = (result.awayScore, result.homeScore)
            default: return nil
            }
            let outcome: TeamOutcome = scored > conceded ? .win : scored == conceded ? .draw : .loss
            return (round, FormEntry(roundNumber: round, outcome: outcome))
        }
        return played.sorted { $0.round > $1.round }.prefix(limit).map(\.entry)
    }
}
