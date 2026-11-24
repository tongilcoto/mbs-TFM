public import Domain

/// Las tarjetas de los partidos (§3.2, R7.8). **Solo ve las no borradas** (`D-36`).
public protocol CardRepository: Sendable {
    func find(_ id: CardID) async throws -> Card?

    /// Las de un partido, acotadas al equipo si se pide, y al jugador si se pide (las
    /// dos puertas se combinan, `D-47`). **Por minuto**, las que no tienen al final.
    func list(matchID: MatchID, teamID: TeamID?, playerID: PlayerID?) async throws -> [Card]

    /// El historial de un jugador. Sin orden: lo pone el caso de uso, que sabe la
    /// fecha de cada partido.
    func list(playerID: PlayerID) async throws -> [Card]

    /// *Upsert* por `id`; el id lo pone el caso de uso.
    func save(_ card: Card) async throws

    /// Borrado **lógico** (`D-36`).
    func delete(_ id: CardID) async throws
}
