public import Domain

/// Los goles de los partidos (§3.2, R7.7). **Solo ve los no borrados** (`D-36`).
public protocol GoalRepository: Sendable {
    func find(_ id: GoalID) async throws -> Goal?

    /// Una página de goles con el filtro, y cuántos lo cumplen. **Con el partido en
    /// el ámbito, por minuto** (los que no tienen, al final); **sin él, por fecha de
    /// partido, de lo más reciente a lo más antiguo** (§5.3).
    func list(_ filter: GoalFilter, page: Int, perPage: Int) async throws -> (goals: [Goal], total: Int)

    /// *Upsert* por `id`; el id lo pone el caso de uso.
    func save(_ goal: Goal) async throws

    /// Borrado **lógico** (`D-36`).
    func delete(_ id: GoalID) async throws
}

/// El filtro de `GET /v1/goals`: **las cuatro puertas se combinan** (`D-47`), y los
/// demás acotan.
public struct GoalFilter: Equatable, Sendable {
    public var matchID: MatchID?
    public var scoringTeamID: TeamID?
    public var concedingTeamID: TeamID?
    public var scorer: PlayerID?
    public var assist: PlayerID?
    public var seasonID: SeasonID?
    public var playType: GoalPlayType?

    public init(matchID: MatchID? = nil, scoringTeamID: TeamID? = nil, concedingTeamID: TeamID? = nil,
                scorer: PlayerID? = nil, assist: PlayerID? = nil, seasonID: SeasonID? = nil,
                playType: GoalPlayType? = nil) {
        self.matchID = matchID
        self.scoringTeamID = scoringTeamID
        self.concedingTeamID = concedingTeamID
        self.scorer = scorer
        self.assist = assist
        self.seasonID = seasonID
        self.playType = playType
    }

    /// Si trae alguna de las cuatro puertas: sin ninguna, 400.
    public var hasScope: Bool {
        matchID != nil || scoringTeamID != nil || concedingTeamID != nil || scorer != nil
    }
}
