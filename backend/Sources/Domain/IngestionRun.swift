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

    /// **Qué se sincronizó en esta pasada** (F7).
    ///
    /// Hasta F7 sobraba, porque solo había una clase de pasada. En cuanto la
    /// clasificación tiene su propio `execute`, una competición deja **dos filas
    /// por disparo** y sin esto serían indistinguibles: misma competición, misma
    /// hora, y los contadores del otro a cero — que se lee como *"no hizo nada"*
    /// en vez de como *"esos contadores no van con esto"*.
    ///
    /// No lleva valor por defecto **a propósito**: quien escribe una pasada tiene
    /// que decir de qué es, y el compilador se encarga de preguntárselo. Un
    /// `.calendar` por defecto convertiría un olvido en una fila que miente.
    public let kind: IngestionKind

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

    /// Las filas de clasificación escritas (F7).
    ///
    /// **Están por consistencia, y es la razón entera**: cada entidad que la
    /// ingesta escribe tiene su par `created`/`updated` —clubes, equipos,
    /// jornadas, partidos—. La clasificación escribe una entidad; sin su par
    /// sería la única sin él.
    ///
    /// > **Ojo con el argumento que NO vale, porque es el primero que se ocurre**
    /// > y es falso: *"el volumen de una clasificación es aritmética —16 equipos
    /// > por jornada— así que el contador es deducible"*. Lo deducible es cuántas
    /// > jornadas tiene la **competición**, que es fijo (16 equipos → 30
    /// > jornadas). Lo que estos contadores dicen es cuántas filas escribió
    /// > **esta pasada**, que no se puede reconstruir después: la de régimen
    /// > escribe una jornada, y la primera de un alta a mitad de temporada
    /// > recompone el histórico y escribe veinticinco.
    public var standingRowsCreated: Int = 0
    public var standingRowsUpdated: Int = 0

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
        kind: IngestionKind,
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
        self.kind = kind
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
            id: id, competitionID: competitionID, kind: kind,
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
        timed.standingRowsCreated = standingRowsCreated
        timed.standingRowsUpdated = standingRowsUpdated
        timed.skipped = skipped
        return timed
    }
}

/// Identificador de `IngestionRun` (§4.1).
public struct IngestionRunID: Hashable, Sendable {
    public let raw: UUID
    public init(raw: UUID) { self.raw = raw }
}

/// **Qué sincronizó una pasada** (F7).
///
/// # Por qué existe, y por qué no existía antes
///
/// Hasta F6 la ingesta tenía **una** operación —el calendario— y el registro de
/// `D-85` podía dar por supuesto de qué hablaba. F7 le añade la clasificación
/// con su propio `execute` (§2.3-b), así que la misma competición deja dos filas
/// por disparo y hay que poder decir cuál es cuál. F8 añadirá la tercera.
///
/// # Se añade aquí y en el *spec*, y en ningún sitio más
///
/// Es `String` y `CaseIterable` por el mismo motivo que `IngestionOutcome` y
/// `FederationCode` (`D-02`): el `CHECK` de la columna **se deriva** de
/// `sqlValueList` y no se teclea, así que el caso de F8 lo hereda solo. Lo único
/// que hay que hacer a mano es añadirlo también al `enum` del contrato — y eso
/// tampoco depende de acordarse, porque el `toContract()` del adaptador es un
/// `switch` exhaustivo y no compila sin él (`D-61`).
public enum IngestionKind: String, CaseIterable, Equatable, Sendable {
    /// La pasada de §5.6: el calendario y sus resultados, de la que salen
    /// `Round`, `Match`, `Team` y `OpponentClub`.
    case calendar
    /// La de F7: la clasificación por jornada, ingerida o calculada (`D-15`).
    case standings
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
        /// **F7**: una fila de la clasificación cuyo `codequipo` no casa con
        /// ningún `Team` conocido.
        ///
        /// Es el reverso de `unresolvedTeam`, y por eso no vale aquél: allí el
        /// arrastre va del equipo al partido —*"el partido depende de un equipo
        /// que se quedó fuera"*—, y aquí la fila **es** del equipo desconocido.
        /// Pasa de verdad: la tabla de la federación puede traer un equipo que el
        /// calendario todavía no ha mencionado, porque los partidos que lo
        /// mencionarían son de jornadas que aún no se han ingerido.
        ///
        /// **No hace fallar la pasada** (`D-83`): es una fila menos en una tabla
        /// de dieciséis, y la pasada siguiente —con el calendario ya al día— la
        /// resuelve sola.
        case unknownStandingTeam
    }
}
