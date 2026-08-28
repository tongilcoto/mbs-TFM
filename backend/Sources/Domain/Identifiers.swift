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
