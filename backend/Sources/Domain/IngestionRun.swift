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

    /// **De qué jornada** es esta pasada. Nula cuando no va de una jornada.
    ///
    /// # Era un agujero, no un campo nuevo
    ///
    /// La tabla decía *"qué competición"* y no *"qué jornada"*, y eso bastaba
    /// mientras la única pasada posible era la del calendario — que es
    /// **agnóstica de jornada por construcción**: su endpoint devuelve la
    /// competición entera en una petición (§5.6), así que no hay jornada que
    /// nombrar. La de clasificación es lo contrario: `/api/standings?round=N`
    /// sirve **una**, así que una pasada **es** una jornada, y sin esta columna
    /// las diez de un alta a mitad de temporada serían diez filas idénticas.
    ///
    /// # La pareja se ata, como la de `error`
    ///
    /// `kind == .standings` ⟺ hay jornada. El `init` lo comprueba y el esquema
    /// lo repite con un `CHECK`, que es el mismo trato que recibe
    /// `(outcome == .failed) ⟺ (error != nil)` y por el mismo motivo: una pasada
    /// de clasificación sin jornada no se puede leer, y una de calendario con
    /// jornada dice algo que no es verdad.
    ///
    /// Los goleadores de F8 caen del lado nulo, y el `CHECK` ya lo admitía sin
    /// tocarlo: `LeagueScorer` es **estado vigente único, no *snapshot* por
    /// jornada** (§3.2), así que su pasada es de la competición entera. La
    /// expresión `(kind = 'standings') = (round_id IS NOT NULL)` dice exactamente
    /// eso —*"solo la clasificación lleva jornada"*— y no *"las que no son
    /// calendario la llevan"*, que es lo que habría habido que corregir.
    public let roundID: RoundID?

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

    /// Los goleadores escritos (F8), **y los retirados**, que es el que no tiene
    /// hermano en ninguna otra entidad.
    ///
    /// Los dos primeros son el par de siempre: cada entidad que la ingesta escribe
    /// tiene su `created`/`updated`, y sin ellos los goleadores serían la única
    /// sin él.
    ///
    /// **`leagueScorersRetired` es propio de esta pasada y de ninguna más**,
    /// porque `LeagueScorer` es la única salida de la ingesta que **borra**
    /// (`D-94`). Y es justo el número que hay que poder mirar cuando algo va mal:
    /// una pasada que retire 200 de 218 no ha limpiado nada, ha vaciado el
    /// ranking — y sin contador eso se ve en la pantalla y no en la tabla. Es el
    /// mismo argumento con el que `D-85` existe: la ingesta no tiene usuario
    /// delante.
    public var leagueScorersCreated: Int = 0
    public var leagueScorersUpdated: Int = 0
    public var leagueScorersRetired: Int = 0

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
        roundID: RoundID? = nil,
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
        // La pareja de la jornada, y va antes que la del error porque es la que
        // decide si la fila se puede leer siquiera: diez pasadas de clasificación
        // sin decir de qué jornada son, son diez filas iguales.
        //
        // **El `switch` nombra los tres casos y no usa `default` para los que no
        // son clasificación**: con un `default`, el caso que añada la fase
        // siguiente entraría por él y aceptaría una jornada en silencio. Aquí, el
        // compilador obliga a decidir — que es el criterio de `D-61` y el mismo
        // que sostiene `RFFMGameType` y `toContract()`.
        switch (kind, roundID) {
        case (.standings, nil):
            throw DomainError.invalidValue(
                field: "roundID", reason: "una pasada de clasificación es de una jornada"
            )
        case (.calendar, _?), (.scorers, _?):
            throw DomainError.invalidValue(
                field: "roundID",
                reason: "solo la pasada de clasificación es de una jornada; "
                    + "las demás son de la competición entera"
            )
        case (.calendar, nil), (.scorers, nil), (.standings, _?):
            break
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
        self.roundID = roundID
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
            id: id, competitionID: competitionID, kind: kind, roundID: roundID,
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
        timed.leagueScorersCreated = leagueScorersCreated
        timed.leagueScorersUpdated = leagueScorersUpdated
        timed.leagueScorersRetired = leagueScorersRetired
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
/// `sqlValueList` y no se teclea. Lo único que hay que hacer a mano en el
/// contrato es añadir el caso al `enum` del *spec* — y eso tampoco depende de
/// acordarse, porque el `toContract()` del adaptador es un `switch` exhaustivo y
/// no compila sin él (`D-61`).
///
/// > ⚠️ **Lo que F7 escribió aquí era falso, y F8 lo midió: el caso nuevo NO lo
/// > hereda un *schema* que ya existe.** Decía que *"el caso de F8 lo hereda
/// > solo"*. La derivación ocurre **una sola vez**, cuando la migración corre, y
/// > lo que queda en la base es el texto que salió aquel día:
/// > `CHECK (kind = ANY (ARRAY['calendar','standings']))`, comprobado en
/// > `club_atleti` antes de añadir `scorers`. Es `D-90` un piso más abajo —
/// > **derivado no significa vivo**—, así que **añadir un caso aquí obliga a una
/// > migración nueva** que rehaga el `CHECK` (`AddScorersToIngestionRun`). Sin
/// > ella, un alta limpia acepta la pasada de goleadores y un club vivo la
/// > rechaza con un `23514` que nadie relaciona con un `enum`.
public enum IngestionKind: String, CaseIterable, Equatable, Sendable {
    /// La pasada de §5.6: el calendario y sus resultados, de la que salen
    /// `Round`, `Match`, `Team` y `OpponentClub`.
    case calendar
    /// La de F7: la clasificación por jornada, ingerida o calculada (`D-15`).
    case standings
    /// La de F8: el ranking de goleadores, **de la competición entera** y sin
    /// jornada — `LeagueScorer` es estado vigente único, no *snapshot* (§3.2),
    /// así que esta pasada cae del lado **nulo** de `roundID`.
    case scorers
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

        /// **F8**: una fila del ranking de goleadores sin identificador de
        /// jugador, o que el Dominio rechaza por cualquier otro motivo.
        ///
        /// # Es el único descarte que significa "la fuente ha cambiado", no
        /// "los datos aún no cuadran"
        ///
        /// Los otros ocho describen estados transitorios y legítimos: un equipo
        /// que el calendario no ha visto todavía, una fecha que la federación no
        /// ha publicado, dos candidatos igual de buenos. Éste no: el
        /// `codigo_jugador` viene en **426/426** filas de los volcados medidos
        /// ([Anexo RFFM §F.13], §F.19, [Anexo FCF §C.10.7]), así que su ausencia
        /// es una anomalía y no un compás de espera.
        ///
        /// # Y aun así no hace fallar la pasada, al revés que en la clasificación
        ///
        /// Porque un ranking **no tiene numeración**: 217 filas de 218 siguen
        /// siendo un ranking utilizable. Una clasificación a la que le falte una
        /// fila tiene un hueco en una numeración que el *spec* declara imposible,
        /// y por eso allí el parser exige y aquí se descarta. Es `D-75` aplicado a
        /// dos formas distintas de tabla: los dos errores no cuestan lo mismo en
        /// una y en la otra.
        case unidentifiedScorer
    }
}
