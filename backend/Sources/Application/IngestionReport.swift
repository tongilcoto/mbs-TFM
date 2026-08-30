public import struct Foundation.Date
public import Domain

/// Lo que una pasada de ingesta deja dicho de sí misma.
///
/// # Por qué la cadena devuelve esto y no escribe una columna
///
/// §3.7 remata el paso 3 con *"alta nueva **marcada para revisión manual**"*, y
/// `D-79` cerró que esa marca **no es una columna**: lo que hace revisable un
/// emparejamiento es por qué escalón se supo y qué se quedó fuera, y eso viaja
/// en el resultado de la pasada. Este tipo es ese resultado.
///
/// Hoy lo devuelve el caso de uso y lo consume quien lo llame. Es también lo que
/// tendrá que persistir la tabla de registro de ingestas cuando se decida su
/// fase, y por eso los motivos son un enumerado cerrado y no texto libre.
public struct IngestionReport: Equatable, Sendable {
    public let competitionID: CompetitionID

    /// El instante que se escribió en `Competition.lastSyncedAt`. Sale del
    /// puerto `Clock`, no de un `Date()`.
    public let syncedAt: Date

    public var opponentClubsCreated: Int = 0
    public var opponentClubsUpdated: Int = 0
    public var teamsCreated: Int = 0
    public var teamsUpdated: Int = 0
    public var roundsCreated: Int = 0
    public var roundsUpdated: Int = 0
    public var matchesCreated: Int = 0
    public var matchesUpdated: Int = 0

    /// Lo que la pasada **no** escribió, y por qué. Vacío es el caso normal.
    public var skipped: [IngestionSkip] = []

    public init(competitionID: CompetitionID, syncedAt: Date) {
        self.competitionID = competitionID
        self.syncedAt = syncedAt
    }
}

/// Una fila que la pasada dejó fuera.
///
/// **No es un error**: la pasada sigue. Es material para la operación de fusión
/// de §9 y para que un humano sepa qué mirar.
public struct IngestionSkip: Equatable, Sendable {
    public let reason: Reason

    /// Con qué se puede encontrar la fila en la fuente: el nombre del equipo, el
    /// `codacta`, lo que haya. **Texto**, porque va a un informe que lee una
    /// persona, no a una consulta.
    public let detail: String

    public init(reason: Reason, detail: String) {
        self.reason = reason
        self.detail = detail
    }

    public enum Reason: String, Equatable, Sendable {
        /// `D-79`: el paso 2 encontró dos clubes igual de buenos. Ni se elige ni
        /// se crea.
        case ambiguousOpponentClub
        /// `D-79` en equipos.
        case ambiguousTeam
        /// `D-79` en partidos. Solo puede pasar si el `UNIQUE` de coordenadas no
        /// estuviera, así que aquí es señal de esquema roto más que de datos.
        case ambiguousMatch
        /// El partido depende de dos equipos, y uno de ellos se quedó fuera. No
        /// es un problema del partido: es el arrastre del anterior.
        case unresolvedTeam
        /// `match_date` es `NOT NULL` (§3.2) y la fuente no publicó fecha.
        /// Inventarla sería lo que `D-75` prohíbe.
        case missingMatchDate
        /// `D-82`: del nombre no queda nada de lo que derivar un slug.
        case unsluggableClubName
    }
}
