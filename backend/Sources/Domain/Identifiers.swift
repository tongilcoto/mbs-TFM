public import struct Foundation.UUID

/// Identificadores tipados (§4.1).
///
/// Un `UUID` desnudo deja pasar el id de un equipo donde se espera el de un
/// jugador; esto lo convierte en **error de compilación**, no de ejecución.
/// `Foundation` es la única dependencia del Dominio, y es biblioteca estándar,
/// no framework: la Regla de dependencia (§2.2) prohíbe Vapor y Fluent, no `UUID`.
public struct ClubID: Hashable, Sendable {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

/// Temporada (§4.2, raíz de agregado).
public struct SeasonID: Hashable, Sendable {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

/// Competición (§4.2, raíz de agregado).
public struct CompetitionID: Hashable, Sendable {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

/// Club rival (§3.2). **Identidad del club, separada de sus equipos** (§3.6): un
/// club rival tiene equipo en varias categorías y todos apuntan a esta misma fila.
public struct OpponentClubID: Hashable, Sendable {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

/// Equipo (§3.2). Propio si `opponentClubID` es nulo, rival si no ([D-03], §3.6).
public struct TeamID: Hashable, Sendable {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

/// Jornada (§3.2). Fija la competición del partido, y por eso la clave de
/// coordenadas de `Match` no repite `competition_id` (§3.5).
public struct RoundID: Hashable, Sendable {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

/// Partido (§4.2, raíz de agregado).
public struct MatchID: Hashable, Sendable {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}
