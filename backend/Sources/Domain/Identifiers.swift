public import struct Foundation.UUID

/// Identificadores tipados (§4.1).
///
/// Un `UUID` desnudo deja pasar el id de un equipo donde se espera el de un
/// jugador; esto lo convierte en **error de compilación**, no de ejecución.
/// `Foundation` es la única dependencia del Dominio, y es biblioteca estándar,
/// no framework: la Regla de dependencia (§2.2) prohíbe Vapor y Fluent, no `UUID`.
///
/// # Y además saben escribirse, que es lo que arregla `F10-ter`
///
/// Un `UUID` se puede escribir en mayúsculas o en minúsculas sin cambiar de
/// valor —`4BCA` y `4bca` son el mismo número—, así que la forma **hay que
/// elegirla**, y RFC 4122 §3 la eligió: **minúscula**. Foundation entrega
/// mayúsculas, de modo que la conversión hace falta **en todas partes**.
///
/// Antes de este protocolo no vivía en ningún sitio: se repetía a mano en cada
/// punto de salida. Medido el 2026-09-25, el reparto era **14 sitios que se
/// acordaban y 14 que no** —los segundos, al meter el id en el texto de un
/// error—, con el resultado de que un cliente que comparase el `detail` de un
/// problema contra el id que envió **no casaba**.
///
/// El reparto mitad y mitad es el argumento entero: no falló la gente, faltaba
/// el sitio. Ahora **lo decide el tipo**, una sola vez, y quien necesite el
/// `UUID` desnudo sigue teniendo `raw`.
public protocol TypedIdentifier: Hashable, Sendable, CustomStringConvertible {
    var raw: UUID { get }
    init(raw: UUID)
}

extension TypedIdentifier {
    /// La forma canónica de RFC 4122 §3: **minúscula**, que es la que viaja en
    /// todo cuerpo del contrato y la que un cliente puede comparar con lo que
    /// envió.
    public var description: String { raw.uuidString.lowercased() }
}

/// Club (§4.2, raíz de agregado). Hay **uno por tenant** (§6.1), así que este id
/// no elige nada: lo elige el *schema*.
public struct ClubID: TypedIdentifier {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

/// Temporada (§4.2, raíz de agregado).
public struct SeasonID: TypedIdentifier {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

/// Competición (§4.2, raíz de agregado).
public struct CompetitionID: TypedIdentifier {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

/// Club rival (§3.2). **Identidad del club, separada de sus equipos** (§3.6): un
/// club rival tiene equipo en varias categorías y todos apuntan a esta misma fila.
public struct OpponentClubID: TypedIdentifier {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

/// Equipo (§3.2). Propio si `opponentClubID` es nulo, rival si no ([D-03], §3.6).
public struct TeamID: TypedIdentifier {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

/// Inscripción de un equipo en una temporada (§3.2, `D-68`).
///
/// **Existe porque toda tabla tiene PK**, igual que `StandingRowID`, y no porque
/// haya un recurso que lo exponga: la ruta es
/// `PUT /v1/teams/{teamId}/registrations/{seasonId}`, así que **el par (equipo,
/// temporada) es el recurso** y este id no sale nunca del sistema. Que no haya
/// `{registrationId}` en ninguna ruta es deliberado: ése fue el síntoma que
/// delató a `Participation` en su día (`D-27`).
public struct TeamRegistrationID: TypedIdentifier {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

/// Jornada (§3.2). Fija la competición del partido, y por eso la clave de
/// coordenadas de `Match` no repite `competition_id` (§3.5).
public struct RoundID: TypedIdentifier {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

/// Partido (§4.2, raíz de agregado).
public struct MatchID: TypedIdentifier {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

/// Fila de clasificación (§3.2, **entidad 9**).
///
/// **Existe porque toda tabla tiene PK** (§3.5), no porque haya un endpoint que
/// la sirva: `StandingRow` es un modelo de lectura sin `GET /{id}` (`D-34`). Su
/// identidad de negocio es la pareja (jornada, equipo), que es el `UNIQUE`.
public struct StandingRowID: TypedIdentifier {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

/// Fila del ranking de goleadores (§3.2, **entidad 15**).
///
/// **Existe porque toda tabla tiene PK** (§3.5), igual que `StandingRowID`, y
/// tampoco tiene `GET /{id}` (`D-34`). Su identidad de negocio es
/// (competición, `federation_player_id`), que es el `UNIQUE` de `D-93`.
public struct LeagueScorerID: TypedIdentifier {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}
