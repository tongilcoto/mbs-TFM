public import struct Foundation.Date
public import struct Domain.SeasonLabel
public import struct Domain.WallClockTime
public import enum Domain.Modality

/// Puerto de salida hacia la API de la federación (§4.3, §5.6).
///
/// Lo implementa **un adaptador por federación** —el catálogo en código de
/// `D-17`— y lo usan los dos únicos clientes que hay: el **job** de ingesta
/// (§2.3-b) y el caso de uso de ***preview*** del BFF (§2.3-c). No hay más:
/// este módulo **no expone superficie HTTP propia** y **no hay proxy a la
/// federación** (§5.6).
///
/// # Sin estado, y no es un detalle de estilo
///
/// La implementación previa en la app iOS `rffm-agenda-ios` guarda estado mutable
/// entre llamadas: su `FCFContext` es una clase `@unchecked Sendable` que recuerda
/// la temporada y la categoría de una llamada para usarlas en la siguiente. En un
/// backend concurrente y **multi-tenant** eso es una fuga entre peticiones
/// esperando a ocurrir (Plan §7.2). **Lo que la segunda llamada necesita, se le
/// pasa**: por eso `fetchCalendar` recibe la coordenada entera y no hay `setUp`
/// ni propiedades que recordar.
///
/// # Lo que este puerto todavía no tiene
///
/// Clasificación (F7), goleadores (F8) y acta (`D-57`). Se añaden cuando su fase
/// los pida, no antes: una firma inventada hoy se escribiría contra un anexo y no
/// contra un volcado.
///
/// > ⚠️ **Antes de añadir el segundo método, leer F6-bis del Plan de desarrollo.**
/// > El bloque `A-1` de la auditoría midió este puerto contra el volcado de la FCF
/// > y el resultado se parte en dos: `FederationMatch` y `FederationTeamRef`
/// > aguantan **campo a campo**, y el **sobre** de `FederationCalendar` estaba
/// > cortado a la medida de la RFFM —de sus cinco campos esa fuente publica
/// > **uno**, y los dos obligatorios eran justo los dos que no tiene (H-08)—.
/// >
/// > **F6-bis ya arregló el sobre de este método**: `FederationRound.label`
/// > **desapareció** (no lo leía nadie) y `seasonLabel` es **opcional**. Lo que
/// > queda vivo es la regla para los que vienen: **no copiar la forma del sobre
/// > en los DTOs de F7 y F8.** La asimetría se repite ahí: `/api/standings` y
/// > `/api/scorers` de la RFFM devuelven `competicion` y `grupo`
/// > ([Anexo RFFM §F.8], §F.13) y sus equivalentes de la FCF no
/// > ([Anexo FCF §C.10.6], §C.10.7). Un sobre nuevo modelado por analogía
/// > reproduce el problema dos veces más antes de que exista el segundo adaptador.
/// >
/// > **Y la evidencia de la coordenada no vive en el sobre** (`D-91`): ni la
/// > etiqueta de temporada —que en la RFFM es el **eco** de lo que enviamos— ni
/// > el nombre de la competición —que es **idéntico entre temporadas**
/// > ([Anexo RFFM §F.17])— prueban de qué año es un calendario. Lo prueban las
/// > **fechas de los partidos**, y esas ya están en `FederationMatch`. Un DTO de
/// > F7 o F8 que quiera ser verificable necesita traer **algo que no pueda ser
/// > eco**; si no lo tiene, la verificación se apoya en el calendario.
/// >
/// > **La coordenada, en cambio, no hay que tocarla** (H-14): ninguno de los
/// > cuatro endpoints pide un cuarto eje, y **la jornada de F7 va como parámetro
/// > del método** —`fetchStandings(_:round:)`— porque es de la operación y no de
/// > la competición. La FCF la ignora, y eso **es** `providesRoundStandings`
/// > (`D-55`) visto desde aquí: quien decide qué hacer con ella es el caso de uso,
/// > que ya lee el catálogo del Dominio.
public protocol FederationClient: Sendable {
    /// El calendario completo del grupo, tal y como lo publica la federación.
    ///
    /// **No persiste nada y no empareja nada**: devuelve lo que la fuente dice.
    /// Casar eso con lo que ya hay en la base de datos es la cadena de §3.7, que
    /// vive en el **Dominio** —`MatchingChain`, F4— y no aquí. Lo que sí es de
    /// esta capa es el caso de uso que carga los candidatos, llama a la cadena y
    /// escribe el resultado (F5).
    func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar
}

/// Las coordenadas con las que se llama a una federación (§3.7).
///
/// **Las tres primeras son las columnas del modelo**, y `D-74` cerró que las dos
/// federaciones soportadas las usan igual: tres códigos, uno por columna, sin
/// componer rutas.
///
/// `modality` **no es una columna**: es la contrapartida de dominio del
/// `tipojuego` de la RFFM (§3.2, `D-07`), que no se almacena porque cada
/// federación lo codifica a su manera. El adaptador lo traduce al llamar.
public struct FederationCoordinate: Hashable, Sendable {
    /// `temporada=22` — de `Season.federationSeasonID`.
    public let federationSeasonID: String
    /// `competicion=26737701` — categoría de edad **+** división.
    public let federationCompetitionID: String
    /// `grupo=26737702` — **solo** el grupo.
    public let federationGroupID: String
    /// De `Competition.modality`. Se codifica al llamar, no se guarda.
    public let modality: Modality

    public init(
        federationSeasonID: String,
        federationCompetitionID: String,
        federationGroupID: String,
        modality: Modality
    ) {
        self.federationSeasonID = federationSeasonID
        self.federationCompetitionID = federationCompetitionID
        self.federationGroupID = federationGroupID
        self.modality = modality
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Lo que la federación dice
//
// **Estos DTOs se rediseñan, no se copian** (Plan §7.2, punto 3). El `Match` de
// la app iOS es un modelo de **pantalla**: fecha y hora son `String` y **no lleva
// ningún identificador de federación** — ni `codacta`, ni `codigo_equipo`. Le
// falta justo lo que sostiene la cadena de emparejamiento de §3.7 y el
// `federation_match_id` de `D-31`.
//
// Y no son entidades de dominio: describen **lo que dijo una fuente ajena**, con
// sus huecos. De ahí que casi todo sea opcional — un `nil` aquí significa "la
// fuente no lo dijo", que es exactamente la distinción sobre la que `D-56`
// construye la política de *upsert*.
// ─────────────────────────────────────────────────────────────────────────────

/// El calendario de un grupo, completo.
public struct FederationCalendar: Equatable, Sendable {
    /// Ya en el formato del modelo (`"2026/27"`), reformateada por el adaptador
    /// (`D-71`): el Dominio no conoce el rótulo de ninguna federación.
    ///
    /// **Opcional desde F6-bis** (`A-1`/H-08, H-10), y por tres razones que se
    /// refuerzan:
    ///
    /// 1. **La FCF no la publica.** Su calendario trae 21 claves y ninguna de
    ///    sobre: ni temporada, ni nombre de competición, ni rótulo de jornada
    ///    ([Anexo FCF §C.10.4]). Un campo obligatorio que una de las dos fuentes
    ///    no puede llenar obliga a inventarlo en el adaptador, que es lo que
    ///    este puerto dice de sí mismo que no hay que hacer.
    /// 2. **Era un *Value Object* con invariante dura en medio del sobre.** Si
    ///    la RFFM devolviera `"2026-2028"`, `SeasonLabel` lanzaba y se caía el
    ///    `fetchCalendar` **entero**, con sus 30 jornadas ya parseadas detrás —
    ///    y su único lector en todo el backend es `seed-competition`, que es
    ///    herramienta y no contrato (H-10).
    /// 3. **En la RFFM es el eco de nuestro propio parámetro** ([Anexo RFFM
    ///    §F.16]), así que como evidencia vale **cero**: quien compare esto con
    ///    `Season.label` estará comparando un dato consigo mismo. La evidencia de
    ///    temporada son **las fechas** (`D-91`).
    public let seasonLabel: SeasonLabel?

    /// El nombre **literal** que la federación da a la competición.
    ///
    /// Va a `Competition.federation_name`, que es **evidencia y no rótulo**
    /// (`D-72`): de este texto sale la inferencia de `gender`
    /// ([Anexo RFFM §F.14]).
    public let competitionName: String?

    /// Rótulo del grupo (`"Grupo 1"`). **No es deducible del id** (§3.7): uno se
    /// muestra, el otro se llama.
    public let groupLabel: String?

    /// La jornada en curso según la fuente. **El mejor disparador para una
    /// ingesta incremental**, y la app heredada no lo usaba ([Anexo RFFM §F.7]).
    public let currentRound: Int?

    public let rounds: [FederationRound]

    public init(
        seasonLabel: SeasonLabel?,
        competitionName: String?,
        groupLabel: String?,
        currentRound: Int?,
        rounds: [FederationRound]
    ) {
        self.seasonLabel = seasonLabel
        self.competitionName = competitionName
        self.groupLabel = groupLabel
        self.currentRound = currentRound
        self.rounds = rounds
    }
}

/// Una jornada.
///
/// # Lo que este tipo **tenía** y se quitó en F6-bis
///
/// Llevaba un `label: String` **obligatorio** con el rótulo de la RFFM tal cual
/// (`"1 (13-09-2026)"`), conservado *"porque lleva dentro la fecha nominal de la
/// jornada"*. Se quita por dos motivos medidos (`A-1`/H-08):
///
/// - **No lo leía nadie.** Su única aparición en todo el backend era
///   `self.label = label`. La fecha nominal que justificaba guardarlo no la usa
///   ninguna regla: `D-81` calcula el rango de la jornada **de las fechas de sus
///   partidos**, que es dato y no rótulo.
/// - **La FCF no tiene equivalente**, así que el adaptador catalán tendría que
///   fabricarlo — un `"Jornada 3"` compuesto por nosotros con pinta de venir de
///   la fuente, que es la clase de eco del que avisa [Anexo RFFM §F.16].
///
/// Si algún día hace falta esa fecha nominal, está en el volcado y se añade
/// **cuando exista el lector**, no antes.
public struct FederationRound: Equatable, Sendable {
    /// El número, **del campo `codjornada`**. Ni del índice del array (que es lo
    /// que hacía la app heredada) ni del campo `jornada`, que es un rótulo
    /// ([Anexo RFFM §F.15]).
    public let number: Int

    public let matches: [FederationMatch]

    public init(number: Int, matches: [FederationMatch]) {
        self.number = number
        self.matches = matches
    }
}

/// Un partido, tal y como lo publica la fuente.
public struct FederationMatch: Equatable, Sendable {
    /// `codacta` en la RFFM. **Anulable** porque es un campo *de la RFFM* y no del
    /// contrato genérico de federación (`D-31`) — aunque en la práctica venga
    /// siempre ([Anexo RFFM §F.12], §F.15).
    public let federationMatchID: String?

    public let home: FederationTeamRef
    public let away: FederationTeamRef

    /// `nil` ⇒ **la fuente no dijo nada**, que no es lo mismo que `0` (§F.11).
    public let homeScore: Int?
    public let awayScore: Int?

    /// Fecha de calendario, **separada de la hora** (`D-30`): hasta que la
    /// federación fija la franja, lo que hay es "sábado, hora por decidir".
    public let date: Date?
    public let kickoff: WallClockTime?

    public let venue: String?
    /// Existe identificador de campo. Hoy el modelo no lo usa —`Match.venue` es
    /// texto libre— pero se transporta: si algún día el campo merece entidad
    /// propia, aquí está la clave ([Anexo RFFM §F.5]).
    public let venueCode: String?

    public init(
        federationMatchID: String?,
        home: FederationTeamRef,
        away: FederationTeamRef,
        homeScore: Int?,
        awayScore: Int?,
        date: Date?,
        kickoff: WallClockTime?,
        venue: String?,
        venueCode: String?
    ) {
        self.federationMatchID = federationMatchID
        self.home = home
        self.away = away
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.date = date
        self.kickoff = kickoff
        self.venue = venue
        self.venueCode = venueCode
    }
}

/// Un equipo mencionado en un partido.
///
/// **La fuente no distingue equipo propio de rival** —ni puede—, así que esto es
/// lo mismo para los dos. Quién es de casa lo decide el emparejamiento (§3.7,
/// `D-66`), no el adaptador.
public struct FederationTeamRef: Equatable, Sendable {
    /// `codigo_equipo`: identifica al **equipo**, no al club — dos equipos del
    /// mismo club tienen códigos distintos pese a compartir nombre y escudo
    /// ([Anexo RFFM §F.3]).
    public let federationTeamID: String?

    /// El nombre **sin la letra**, tal y como lo publica la fuente. No se corrige
    /// la grafía: es campo *descriptivo* y el valor bueno acaba siendo el del
    /// administrador (§3.7).
    public let name: String

    /// La letra que distingue al *"Infantil A"* del *"Infantil B"* del mismo
    /// club, ya separada del nombre. Opcional: hay clubes sin filial.
    ///
    /// **Cómo se separe es del adaptador**, y cada fuente la escribe a su manera
    /// —la RFFM la embebe entre comillas simples al final del nombre
    /// ([Anexo RFFM §F.5])—. Lo que este campo promete es que **aquí ya viene
    /// suelta**: el Dominio no parsea nombres (`NormalizedName`), y la letra
    /// entra en la clave única de `Team` (`D-77`), así que no es cosmética.
    public let letter: String?

    /// El **club**, no el equipo. `nil` cuando la fuente no lo da o el adaptador
    /// no logra sacarlo: §3.7 exige que la ingesta **tolere el fallo y degrade**,
    /// y el paso 2 de la cadena de emparejamiento existe para eso.
    ///
    /// **De dónde sale es del adaptador, y no es lo mismo en las dos fuentes.**
    /// La FCF lo publica como campo propio (`CODCLUB_*`, [Anexo FCF §C.10.4]); la
    /// RFFM no tiene campo de club y hay que inferirlo del nombre del fichero del
    /// escudo ([Anexo RFFM §F.4]), que es una inferencia y no un contrato — de ahí
    /// que este campo sea anulable.
    ///
    /// > ⚠️ **El patrón del escudo es el mismo en las dos y el número no
    /// > significa lo mismo.** `00100_<10 dígitos>_<texto>` existe en ambas
    /// > ([Anexo FCF §C.10.4] lo señala como prueba de plataforma común), pero en
    /// > la FCF ese número **no es el club**: `00100_0001223396_MANLLEU.png`
    /// > convive con `CODCLUB_CASA: "1023"`. Generalizar la inferencia de Madrid
    /// > por parecido de formato escribiría aquí un número que no es la clave de
    /// > club de esa federación — y la cadena de §3.7 empareja por ella.
    public let federationClubID: String?

    /// URL **absoluta** del escudo, ya compuesta por el adaptador.
    ///
    /// Absoluta y no relativa porque el *host* no es constante nuestra: la RFFM lo
    /// publica dentro de la propia respuesta ([Anexo RFFM §F.15]) y cada fuente lo
    /// resuelve como pueda. Lo que el puerto entrega es algo de lo que se pueda
    /// descargar sin saber de quién vino.
    ///
    /// El modelo **no guarda esta URL**: descarga el fichero y guarda la clave del
    /// objeto en Storage (`crest_key`, `D-19`). Aquí es de dónde bajarlo.
    public let crestURL: String?

    public init(
        federationTeamID: String?,
        name: String,
        letter: String?,
        federationClubID: String?,
        crestURL: String?
    ) {
        self.federationTeamID = federationTeamID
        self.name = name
        self.letter = letter
        self.federationClubID = federationClubID
        self.crestURL = crestURL
    }
}
