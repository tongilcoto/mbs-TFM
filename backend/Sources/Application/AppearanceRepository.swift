public import Domain

/// La convocatoria de los partidos (§3.2, R7.6). **Solo ve las no borradas**: el
/// borrado es lógico (`D-36`) y, para el club, es «no convocado» (`D-134`).
public protocol AppearanceRepository: Sendable {
    func find(_ id: AppearanceID) async throws -> Appearance?

    /// La convocatoria de un partido, acotada al equipo del apunte si se pide (el
    /// derbi entre dos equipos del club, §5.1). **Por dorsal del acta**, los que no
    /// tienen al final, y en el orden en que se apuntaron.
    func list(matchID: MatchID, teamID: TeamID?) async throws -> [Appearance]

    /// El historial de un jugador (la fila de una temporada, `D-05`). Sin orden: lo
    /// pone el caso de uso, que sabe la fecha de cada partido.
    func list(playerID: PlayerID) async throws -> [Appearance]

    /// **Las de un equipo en una temporada** (R7.9, los refuerzos): las que llevan
    /// ese equipo, de los partidos de esa temporada (`D-28`). Sin orden.
    func list(teamID: TeamID, seasonID: SeasonID) async throws -> [Appearance]

    /// La de un jugador en un partido, si la hay: la unicidad de §3.5.
    func find(playerID: PlayerID, matchID: MatchID) async throws -> Appearance?

    /// *Upsert* por `id`; el id lo pone el caso de uso.
    func save(_ appearance: Appearance) async throws

    /// Borrado **lógico** (`D-36`): la fila deja de verse y el jugador queda «no
    /// convocado».
    func delete(_ id: AppearanceID) async throws
}
