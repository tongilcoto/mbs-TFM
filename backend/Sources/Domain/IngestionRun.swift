public import struct Foundation.Date
public import struct Foundation.UUID

/// **El registro de una pasada de ingesta**: qué se sincronizó, cuándo, cómo
/// acabó y qué se quedó fuera.
///
/// # Por qué es una entidad y no solo el valor que devuelve el caso de uso
///
/// Empezó siendo eso —un `IngestionReport` en Aplicación— y se quedó corto por
/// una razón operativa: **la ingesta no tiene usuario delante** (§2.3-b). Es un
/// job que corre solo, de madrugada y por tenant, así que si lo que dice de sí
/// misma no se guarda, no lo lee nadie. La pregunta que esta tabla existe para
/// contestar es *"¿por qué falta este partido?"*, y se hace días después.
///
/// # No contradice `D-79`
///
/// Aquella decisión dice que la *"marca para revisión manual"* de §3.7 **no es
/// una columna**, y sigue sin serlo: lo que aquí se guarda es el registro de la
/// **pasada**, no un estado de la fila emparejada. `OpponentClub` y `Team`
/// siguen sin saber que existen. Si un descarte se resuelve, la fila que lo
/// arreglaría no se toca — se vuelve a pasar, y la pasada siguiente ya no lo
/// reporta.
///
/// # Se escribe en su **propio** ámbito de tenant
///
/// La pasada entera va en una transacción (`D-83`), así que un registro escrito
/// dentro de ella **desaparecería con el `rollback` justo en el caso que más
/// importa**: la pasada que falla. Por eso el registro se escribe después,
/// aparte, gane o pierda (`D-85`).
public struct IngestionRun: Identifiable, Equatable, Sendable {
    public let id: IngestionRunID
    public let competitionID: CompetitionID

    public let startedAt: Date
    public let finishedAt: Date

    public let outcome: IngestionOutcome

    /// El motivo del fallo, si lo hubo. Nulo cuando `outcome` es `.succeeded`.
    ///
    /// **Es texto y no un código**: los fallos que llegan aquí son de la fuente,
    /// del esquema o de una invariante, y enumerarlos sería inventarse una
    /// taxonomía antes de haber visto los casos.
    public let error: String?

    // ── Qué se escribió ─────────────────────────────────────────────────────
    // Ocho contadores planos y no un `jsonb`: son las columnas por las que se va
    // a consultar ("¿qué pasada creó 300 partidos de golpe?").

    public var opponentClubsCreated: Int = 0
    public var opponentClubsUpdated: Int = 0
    public var teamsCreated: Int = 0
    public var teamsUpdated: Int = 0
    public var roundsCreated: Int = 0
    public var roundsUpdated: Int = 0
    public var matchesCreated: Int = 0
    public var matchesUpdated: Int = 0

    /// Lo que la pasada **no** escribió, y por qué. Vacío es el caso normal.
    ///
    /// Va como documento y no como tabla hija: no se consulta por sus campos —se
    /// lee entera, junto a su pasada— y una tabla más significaría una FK, un
    /// borrado en cascada y una consulta con `JOIN` para contestar la única
    /// pregunta que se le hace.
    public var skipped: [IngestionSkip] = []

    public init(
        id: IngestionRunID,
        competitionID: CompetitionID,
        startedAt: Date,
        finishedAt: Date,
        outcome: IngestionOutcome = .succeeded,
        error: String? = nil
    ) throws {
        guard finishedAt >= startedAt else {
            throw DomainError.invalidValue(
                field: "finishedAt", reason: "una pasada no puede acabar antes de empezar"
            )
        }
        // El par que el esquema no puede atar: un fallo sin motivo no se puede
        // depurar, y un éxito con motivo es una contradicción.
        switch (outcome, error) {
        case (.failed, nil):
            throw DomainError.invalidValue(
                field: "error", reason: "una pasada fallida tiene que decir por qué"
            )
        case (.succeeded, _?):
            throw DomainError.invalidValue(
                field: "error", reason: "una pasada con éxito no lleva motivo de fallo"
            )
        default:
            break
        }

        self.id = id
        self.competitionID = competitionID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.outcome = outcome
        self.error = error
    }

    /// `true` si la pasada llegó al final. Es lo que decide si se escribió
    /// `Competition.lastSyncedAt` (§3.2).
    public var succeeded: Bool { outcome == .succeeded }

    /// La misma pasada, con las marcas de tiempo **de quien conoce los dos
    /// extremos**.
    ///
    /// Existe porque el informe se construye al **empezar** la pasada, cuando
    /// todavía no se sabe cuándo va a terminar: con las suyas, toda pasada con
    /// éxito registraba `startedAt == finishedAt` —duración cero— mientras la
    /// fallida sí se medía. La invariante del `init` no lo delataba, porque
    /// `finishedAt >= startedAt` se cumple trivialmente; lo destaparon las
    /// pruebas manuales de F6 al mirar la tabla de verdad.
    ///
    /// Devuelve una copia y revalida por el `init`, que es lo que impide colar
    /// aquí un par de fechas al revés.
    public func timed(from startedAt: Date, to finishedAt: Date) throws -> IngestionRun {
        var timed = try IngestionRun(
            id: id, competitionID: competitionID,
            startedAt: startedAt, finishedAt: finishedAt,
            outcome: outcome, error: error)
        timed.opponentClubsCreated = opponentClubsCreated
        timed.opponentClubsUpdated = opponentClubsUpdated
        timed.teamsCreated = teamsCreated
        timed.teamsUpdated = teamsUpdated
        timed.roundsCreated = roundsCreated
        timed.roundsUpdated = roundsUpdated
        timed.matchesCreated = matchesCreated
        timed.matchesUpdated = matchesUpdated
        timed.skipped = skipped
        return timed
    }
}

/// Identificador de `IngestionRun` (§4.1).
public struct IngestionRunID: Hashable, Sendable {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

/// Cómo acabó la pasada (§3.3).
///
/// **Dos valores y no cuatro.** La tentación es un `.partial` para la pasada que
/// escribió pero dejó filas fuera; no existe porque `D-83` no lo permite: la
/// pasada es atómica, así que o se escribió entera o no se escribió nada. Que
/// haya descartes **no** la hace parcial — un partido sin fecha es un dato que la
/// fuente no ha publicado todavía, no un fallo de la pasada.
public enum IngestionOutcome: String, CaseIterable, Equatable, Sendable {
    case succeeded
    case failed
}

/// Una fila que la pasada dejó fuera.
///
/// **No es un error**: la pasada sigue. Es material para la operación de fusión
/// de §9 y para que un humano sepa qué mirar.
public struct IngestionSkip: Equatable, Sendable, Codable {
    public let reason: Reason

    /// Con qué se puede encontrar la fila en la fuente: el nombre del equipo, el
    /// `codacta`, lo que haya. **Texto**, porque va a un informe que lee una
    /// persona, no a una consulta.
    public let detail: String

    public init(reason: Reason, detail: String) {
        self.reason = reason
        self.detail = detail
    }

    public enum Reason: String, Equatable, Sendable, Codable, CaseIterable {
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
        /// §3.5 declara `OpponentClub(name)` **único**, y la cadena puede
        /// producir el intento de crear un segundo club con el mismo nombre
        /// literal —descarta al candidato cuya clave de federación contradice y
        /// cae al paso 3—. Sin este desenlace, esa fila reventaría el `UNIQUE` y
        /// con él la transacción de toda la pasada.
        case duplicateClubName
    }
}
