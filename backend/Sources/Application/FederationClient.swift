public import struct Foundation.Date
public import struct Domain.SeasonLabel
public import struct Domain.WallClockTime
public import enum Domain.Modality

/// Puerto de salida hacia la API de la federación (§4.3, §5.6).
///
/// Lo implementa **un adaptador por federación** —el catálogo en código de
/// `D-17`— y lo usan tres casos de uso, siempre a través del proveedor
/// (`FederationClientProvider`): la **ingesta** (`IngestClubCalendars`, §2.3-b),
/// el ***preview*** del enganche (`PreviewFederationLink`, §2.3-c) y **el
/// enganche** mismo (`LinkTeamToFederation`, F10). Fuera de eso solo está
/// `seed-competition`, que es herramienta y no contrato, y llama al adaptador
/// de la RFFM directamente (A-9·H-94). Este módulo **no expone superficie
/// HTTP propia** y **no hay proxy a la federación** (§5.6).
///
/// # Lo que cada adaptador promete
///
/// Son las obligaciones que el tipo no puede imponer y que el núcleo da por
/// cumplidas. Reunidas en A-9 para que el segundo adaptador las encuentre
/// juntas; el detalle está en cada campo:
///
/// 1. **"No hay nada" se dice con `coordinateNotFound`, sin afirmar que la
///    coordenada no exista**: la misma respuesta puede ser pasajera
///    (`FederationError.coordinateNotFound`, H-91).
/// 2. **El código de competición del sobre solo se trae si no es eco.** Si la
///    ruta lo recibió como parámetro, va `nil`
///    (`FederationStanding.federationCompetitionID`, H-97).
/// 3. **Un mismo equipo lleva el mismo `federationTeamID` en todos los
///    métodos.** Si la fuente usa espacios distintos, traducir es del
///    adaptador (`FederationTeamRef.federationTeamID`, H-98).
/// 4. **Un `String` obligatorio que falte se entrega como `""`, no
///    inventado** (la cabecera *"Lo que la federación dice"*, H-99).
/// 5. **La URL que no es suya se rechaza**, porque el llamante no sabe de qué
///    federación es (`coordinate(fromCalendarURL:)`, `D-97`).
/// 6. **El ranking de goleadores es completo**: todo el que ha marcado, sin
///    *top-N*, y si la fuente pagina, el adaptador junta las páginas. Lo que no
///    llega se retira (`D-94`), y la guarda que lo protege da por hecho que el
///    total de goles no baja nunca (`IngestScorers.requireGoalsDoNotDecrease`,
///    H-53). **La FCF no la cumple** (su lista es un *top*-50).
///
/// El detalle de cada método, campo a campo, está en la guía de alta de una
/// federación nueva (`docs/API_y_BBDD Guia-Alta-Federacion-001.md`).
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
/// **El acta** (`D-57`), y nada más. Se añade cuando su fase la pida, no antes:
/// una firma inventada hoy se escribiría contra un anexo y no contra un volcado.
///
/// Las dos que llegaron siguieron esa regla al pie de la letra, y las dos
/// cobraron: F7 capturó `/api/standings` **antes** de escribir la firma y lo
/// medido cambió dos decisiones ([Anexo RFFM §F.18]); F8 hizo lo propio con
/// `/api/scorers` y encontró que **no se comporta como su vecina** —exige los dos
/// códigos y valida que sean pareja ([Anexo RFFM §F.19])—, que es justo lo que se
/// habría dado por hecho copiando.
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
/// > **F7 la aplicó, y así se ve en `FederationStanding`:** de las 29 claves que
/// > la RFFM publica por fila y las once del sobre, el DTO lleva **dos** campos de
/// > sobre y los ocho contadores, y los dos de sobre son anulables porque la FCF
/// > no tiene equivalente. Lo que quedó fuera —`fecha_jornada`, `puntos_sancion`,
/// > `promociones[]`, la racha— **no es lo que la fuente no da, sino lo que nadie
/// > lee todavía**.
/// >
/// > **Y F8 la aplicó más fuerte todavía, porque su asimetría es la mayor de las
/// > tres**: `/api/scorers` trae un sobre de cuatro claves y el equivalente
/// > catalán es **un array pelado, sin sobre ninguno**. `FederationScorerTable`
/// > lleva **un** campo de sobre —el nombre, para la guarda de `D-84`— y deja
/// > fuera hasta el `codigo_competicion` que su vecina celebra, porque aquí ese
/// > código **se envía** y por tanto solo podría ser eco.
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

    /// La clasificación **tras la jornada pedida** (F7, `D-55`).
    ///
    /// # Por qué la jornada va aquí y no en la coordenada (H-14)
    ///
    /// Porque es **de la operación, no de la competición**: la coordenada
    /// identifica *qué* liga, y esto dice *qué foto* de ella. Meterla en
    /// `FederationCoordinate` obligaría a inventarle un valor a `fetchCalendar`,
    /// que no la usa.
    ///
    /// # Y quien decide si esta llamada sirve de algo es el caso de uso
    ///
    /// `D-55` midió que la capacidad que separa a las dos federaciones no es
    /// *"¿publica clasificación?"* —las dos la publican— sino **"¿puede servir
    /// una jornada pasada?"**. La FCF **ignora** la jornada y devuelve siempre la
    /// vigente, y eso es `providesRoundStandings` visto desde este puerto. El
    /// adaptador no miente ni lanza por ello: devuelve lo que su fuente da, y
    /// quien sabe si eso vale para la jornada N es el llamante, que lee el
    /// catálogo del Dominio.
    ///
    /// # Qué significa que no esté
    ///
    /// `FederationError.coordinateNotFound` si la coordenada no designa nada —y
    /// **no es un 404**: en la RFFM llega como `200` con el cuerpo a `null`
    /// ([Anexo RFFM §F.18])—. Y ese `null` llega también, pasajero, con la
    /// coordenada buena (H-61), así que es *"no devolvió nada"* y no *"no
    /// existe"*. Una jornada que la competición no tiene es cosa medida aparte
    /// y hoy sin observar.
    func fetchStandings(
        _ coordinate: FederationCoordinate, round: Int
    ) async throws -> FederationStanding

    /// El **ranking de goleadores** de la competición entera (F8, `D-09`).
    ///
    /// # Sin jornada, y ésa es la diferencia con su vecina
    ///
    /// `fetchStandings` recibe `round:` porque la clasificación **es** la foto de
    /// una jornada. Esto no: `LeagueScorer` es **estado vigente único**, sin
    /// histórico ni columna PREV (§3.2), así que su unidad es la **competición**
    /// —igual que la del calendario— y una pasada deja **una** fila en
    /// `ingestion_runs`, no una por jornada.
    ///
    /// Y la fuente lo confirma: ni `/api/scorers` ni `/api/competition/goleadores`
    /// aceptan jornada ([Anexo RFFM §F.19], [Anexo FCF §C.10.7]). No hay parámetro
    /// que inventar ni que ignorar.
    ///
    /// # Quién decide si esta llamada se hace siquiera
    ///
    /// El caso de uso, leyendo `federationProvidesScorers` del catálogo (`D-48`).
    /// Y aquí esa capacidad pesa **más** que su hermana de la clasificación: con
    /// `false` no hay *fallback* —calcular el ranking desde `Goal` daría el de
    /// nuestra plantilla disfrazado del de la liga (`D-09`)— así que la tabla se
    /// queda vacía y el cliente **oculta la pantalla**. Hoy las dos federaciones
    /// lo publican, así que la guarda no se dispara; existe porque la tercera
    /// podría no hacerlo.
    ///
    /// # Qué significa que no esté
    ///
    /// `FederationError.coordinateNotFound`, y en la RFFM llega como `200` con el
    /// cuerpo a `null`, igual que `/api/standings` — **pero por un motivo más**:
    /// esta ruta exige `idGroup` **e** `idCompetition` y **valida que sean
    /// pareja**, así que un `idCompetition` equivocado o ausente también da `null`
    /// ([Anexo RFFM §F.19]). Es la única ruta medida de la RFFM donde una
    /// coordenada mal tecleada **no** puede servir los datos de otra competición.
    /// Y, como en su vecina, el `null` también llega pasajero con el par bueno
    /// (H-61): no prueba que la coordenada no exista.
    func fetchScorers(
        _ coordinate: FederationCoordinate
    ) async throws -> FederationScorerTable

    /// La **inversa de la coordenada**: qué hay dentro de la URL del calendario
    /// que un administrador acaba de pegar (F10, [D-97], [D-22]).
    ///
    /// # Por qué está en este puerto y no en un puerto aparte
    ///
    /// Porque **el adaptador es dueño del universo de datos de su federación de
    /// punta a punta** —su URL, su JSON, dónde pega la letra del equipo— y nada
    /// de eso es conocimiento del Dominio. El criterio para admitir un método
    /// nuevo aquí es ése, *"¿es conocimiento del universo de esa federación?"*, y
    /// no *"lo necesita un caso de uso"*. La consecuencia a proteger es la de
    /// siempre: **cada federación nueva se escribe sin tocar la anterior**.
    ///
    /// El llamante no sabe —ni puede saber— de qué federación es la URL: llega
    /// hasta aquí por club → `Club.federation` → `FederationClientProvider`. Por
    /// eso **también es cosa del adaptador rechazar la que no es suya**: quien
    /// conoce su propio *host* es él.
    ///
    /// # No es `async`, y eso dice lo que hace
    ///
    /// Es parseo de una cadena, no una pregunta a la fuente. Un adaptador que
    /// necesitara la red para entender su propia URL estaría haciendo otra cosa.
    ///
    /// # Y lo que falta se rechaza, no se completa
    ///
    /// Ningún valor por defecto ([D-22]): inventar una `temporada` ausente sería
    /// elegir por el administrador **cuál** de los calendarios reutilizados se
    /// ingiere, y un dígito de más o de menos no da error — sirve otro calendario
    /// en silencio ([D-84]).
    func coordinate(fromCalendarURL url: String) throws -> FederationCoordinate
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
//
// **Los pocos `String` obligatorios** —`FederationTeamRef.name`,
// `FederationScorerRow.fullName` y `teamLabel`— lo son porque en lo medido
// vienen siempre: más de 1.600 nombres en los volcados y la base de trabajo,
// cero vacíos (A-9). Si una fuente no los diera, el adaptador entrega `""` y
// **no inventa un valor** (`"Desconocido"` pasaría por dato): el Dominio
// rechaza el vacío y la fila se descarta con su motivo, sin tirar la pasada.
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
    ///    `fetchCalendar` **entero**, con sus 30 jornadas ya parseadas detrás.
    ///    Sus lectores solo la usan **para crear una temporada que aún no
    ///    existe**: el *preview* y el enganche (F10) y `seed-competition`. Cuando
    ///    lo escribió H-10, el único era `seed-competition`, y A-9 lo corrigió.
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

    /// La jornada en curso según la fuente.
    ///
    /// **Tiene lector previsto aunque hoy nadie lo lea** (A-9): el backoffice
    /// necesita saber cuál es la jornada en curso. Hasta que esa fase exista,
    /// la cadena se corta aquí —ni `Round` ni el contrato lo recogen—, y por
    /// eso este campo es la excepción declarada a *"un campo sin lector no se
    /// transporta"*: quitarlo obligaría a volver a meterlo. Opcional porque
    /// una fuente puede no publicarlo.
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
    /// El identificador del partido en la federación (`codacta` en la RFFM).
    ///
    /// **Se espera de toda federación**: las dos medidas lo publican, y en las
    /// dos viene siempre ([Anexo RFFM §F.12], §F.15; `CODACTA` en 240 de 240
    /// partidos, [Anexo FCF §C.10.4]). **Y aun así es anulable, de momento**
    /// (`D-31`, enmienda de A-1/H-12): es un campo del proveedor y no del
    /// contrato genérico, puede faltar en una respuesta parcial, y la ingesta no
    /// puede depender de él. Cuando falta, empareja el paso 2 de la cadena
    /// (jornada + local + visitante, §3.7).
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
    /// El identificador del campo de juego, que las dos federaciones publican.
    ///
    /// **Tiene lector previsto aunque hoy nadie lo lea** (A-9): es la clave
    /// para las consultas de direcciones de los mapas, que una clave estable
    /// resuelve mejor que el texto libre de `venue`. Hasta que
    /// esa fase exista, la cadena se corta aquí —`Match.venue` es solo texto y
    /// el contrato no lo expone—, y por eso este campo es la excepción declarada
    /// a *"un campo sin lector no se transporta"*.
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
    ///
    /// **Promesa del puerto, y obligación de cada adaptador** (A-9): un mismo
    /// equipo lleva **el mismo** `federationTeamID` en todos los métodos del
    /// adaptador, en el calendario y en la clasificación. La ingesta empareja la
    /// clasificación **solo** por este campo (`IngestStandings`), sin degradar a
    /// nombre. Si una fuente usa identificadores distintos en cada ruta, traducir
    /// entre ellos es trabajo del adaptador: el núcleo no lo puede hacer. La
    /// RFFM la cumple sin traducción ([Anexo RFFM §F.8], confirmado en §F.18).
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

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - La clasificación (F7)
//
// **Este sobre NO está modelado sobre el del calendario, y es la advertencia que
// el propio puerto se dejó escrita arriba.** `FederationCalendar` se cortó a la
// medida de la RFFM y de sus cinco campos la FCF publica uno (`A-1`/H-08). Aquí
// la asimetría se repite —`/api/standings` devuelve `competicion` y `grupo`, y su
// equivalente catalán no ([Anexo FCF §C.10.6])—, así que **cada campo de abajo
// tiene que justificar que lo lee alguien**, no que la fuente lo publica.
// ─────────────────────────────────────────────────────────────────────────────

/// La clasificación de **una jornada**, tal y como la publica la fuente.
///
/// # Lo que lleva, y quién lo lee
///
/// Solo dos cosas además de las filas, y las dos tienen llamante: la **evidencia
/// de que la coordenada designa lo que creemos** (`D-84`). El resto de lo que la
/// RFFM publica —desglose casa/fuera, `puntos_local`, `coeficiente`, `color` de
/// fila, `promociones[]`, `racha_partidos[]`— **se queda fuera** hasta que exista
/// un lector, que es la regla que F6-bis cobró con `FederationRound.label`:
/// aquel campo llevaba desde F2 sin más aparición que `self.label = label`.
///
/// # Lo que deliberadamente NO lleva, y es la mitad interesante
///
/// - **La jornada.** La respuesta trae `jornada`, y es el **eco** de `round`
///   ([Anexo RFFM §F.18]). Quien llamó ya sabe qué jornada pidió, y publicarlo
///   aquí solo invitaría a "verificarlo" contra sí mismo, que es la trampa de
///   `D-91`.
/// - **`fecha_jornada`.** Ésta **sí** es dato suyo y no eco, y serviría para la
///   guarda de temporada. Pero hoy no la lee nadie —la temporada la valida el
///   calendario, que es quien trae 240 fechas— y un campo sin lector es lo que
///   F6-bis quitó. Está en §F.18 y entra **cuando exista el lector**.
public struct FederationStanding: Equatable, Sendable {
    /// El código de competición que la fuente dice que le corresponde al grupo
    /// pedido.
    ///
    /// **Es la evidencia más fuerte que hay en todo el puerto, y el calendario no
    /// la tiene.** A `/api/standings` se le mandan `idGroup` y `round` y nada
    /// más, así que este código **no puede ser eco** (§F.18): es la fuente
    /// diciendo a qué competición pertenece ese grupo. Comparado con
    /// `Competition.federationCompetitionID` da una igualdad de **identificadores**,
    /// no de rótulos — mientras que la guarda del calendario solo puede comparar
    /// el **nombre**, que `D-91` midió que es idéntico entre temporadas.
    ///
    /// Anulable porque la FCF no publica nada equivalente: obligarlo sería
    /// reproducir H-08 en el sobre siguiente.
    ///
    /// **Y el adaptador solo lo trae si no es eco** (A-9): si su ruta recibe el
    /// código de competición como parámetro, devuelve `nil`. Lo lee
    /// `Competition.requireSameCompetitionCode`, y un eco haría que la guarda
    /// comparase el dato consigo mismo (la trampa de `D-91`).
    public let federationCompetitionID: String?

    /// El nombre literal de la competición, para la guarda de `D-84` que ya
    /// existe (`Competition.requireSameSource`). Anulable por lo mismo.
    ///
    /// > Las dos guardas del sobre se conectaron en A-9. Hasta entonces, este
    /// > tipo decía que tenían llamante y **no lo tenían**: `IngestStandings`
    /// > solo leía las filas.
    public let competitionName: String?

    /// Las filas, **en el orden que publica la fuente**. No se reordenan aquí:
    /// el orden oficial es un dato y `D-92` mide en qué se diferencia del nuestro.
    public let rows: [FederationStandingRow]

    public init(
        federationCompetitionID: String?,
        competitionName: String?,
        rows: [FederationStandingRow]
    ) {
        self.federationCompetitionID = federationCompetitionID
        self.competitionName = competitionName
        self.rows = rows
    }
}

/// Una fila de la clasificación publicada.
///
/// # El equipo es `FederationTeamRef`, y esa reutilización es la decisión
///
/// No un `String` con el nombre ni un id suelto: **el mismo tipo que el
/// calendario**, porque la fila hay que emparejarla con un `Team` por la cadena
/// de §3.7 igual que un partido, y `A-1` midió que `FederationTeamRef` aguanta
/// campo a campo también en la FCF. Con un tipo propio, F7 estaría escribiendo
/// una segunda cadena de emparejamiento para los mismos equipos.
///
/// Y encaja: `codequipo` **es el mismo identificador** que el `codigo_equipo_*`
/// del calendario ([Anexo RFFM §F.8], confirmado en §F.18), así que la unión es
/// por id y no degrada a nombre.
///
/// # Los contadores no son opcionales, al revés que en `FederationMatch`
///
/// Allí un `nil` significa *"la fuente no dijo nada"* y `D-56` construye encima
/// toda la política de *upsert*. Aquí no: una clasificación es un **bloque**, y
/// una fila sin posición o sin puntos no es un dato incompleto, es una tabla
/// rota — con un hueco en la numeración que el *spec* declara imposible
/// (`position`, `minimum: 1`). Así que el parser exige los ocho y falla con
/// `malformedResponse` diciendo cuál faltaba. Medido: 32 filas de dos jornadas,
/// los ocho campos presentes y numéricos en todas.
public struct FederationStandingRow: Equatable, Sendable {
    public let team: FederationTeamRef
    public let position: Int
    public let played: Int
    public let won: Int
    public let drawn: Int
    public let lost: Int
    public let goalsFor: Int
    public let goalsAgainst: Int

    /// Los puntos **que dice la fuente**, sin recalcular.
    ///
    /// El *spec* se comprometió con ello y `puntos_sancion` es la razón: una
    /// tabla con puntos descontados por sanción no cumple `3·G + E`, y es la
    /// tabla oficial. Es además lo único que el *fallback* calculado no puede
    /// reproducir ni en teoría (`D-92`).
    public let points: Int

    public init(
        team: FederationTeamRef,
        position: Int,
        played: Int,
        won: Int,
        drawn: Int,
        lost: Int,
        goalsFor: Int,
        goalsAgainst: Int,
        points: Int
    ) {
        self.team = team
        self.position = position
        self.played = played
        self.won = won
        self.drawn = drawn
        self.lost = lost
        self.goalsFor = goalsFor
        self.goalsAgainst = goalsAgainst
        self.points = points
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Los goleadores (F8)
//
// **Tercer sobre, y la advertencia de F6-bis sigue en pie**: no se modela por
// analogía con los dos anteriores. Cada campo de abajo tiene que justificar que
// **lo lee alguien**, no que la fuente lo publica — que es lo que `A-1`/H-08
// cobró en `FederationCalendar` y lo que F7 aplicó en `FederationStanding`.
//
// Y aquí la asimetría entre fuentes es **la mayor de las tres**, medida:
// `/api/scorers` devuelve un sobre de cuatro claves y `/api/competition/goleadores`
// devuelve **un array pelado, sin sobre ninguno** ([Anexo FCF §C.10.7]). Un DTO
// con campos de sobre obligatorios sería H-08 por tercera vez.
// ─────────────────────────────────────────────────────────────────────────────

/// El ranking de goleadores de una competición, tal y como lo publica la fuente.
///
/// # Lo que lleva, y es **una** cosa además de las filas
///
/// El nombre de la competición, para la guarda de `D-84` que ya existe
/// (`Competition.requireSameSource`). Anulable porque la FCF no publica sobre.
///
/// # Lo que NO lleva, y cada ausencia tiene su motivo medido
///
/// - **El identificador de competición.** `FederationStanding` sí lo lleva, y
///   §F.18 lo celebró como *"la evidencia más fuerte que hay en todo el puerto"*
///   porque a `/api/standings` **no se le envía**. Aquí **sí se envía**
///   (`idCompetition`), así que aunque la respuesta lo trajera sería un **eco** —
///   la trampa de [Anexo RFFM §F.16]—. Y medido: no lo trae.
/// - **`grupo`**, el rótulo. Ya lo trae el calendario y ya se guarda.
/// - **`estado` / `sesion_ok`.** Valen `"1"` en los volcados buenos, lo que invita
///   a usar un `"0"` como señal de error. Con coordenada mala **no llega sobre
///   ninguno**, así que no hay `estado` que mirar (§F.19).
///
/// # Y una ausencia que NO es una decisión, sino un límite de la fuente
///
/// **No hay ni una fecha en toda la respuesta**, así que la guarda de temporada
/// de `D-91` —*"la mediana de las fechas cae dentro de la ventana de la
/// `Season`"*— **no se puede aplicar a este endpoint**. Quien copie los códigos
/// del año pasado recibirá un ranking perfectamente parseable de la temporada
/// anterior, y lo único que lo detecta es el calendario, que sí trae 240 fechas.
/// Está escrito aquí para que nadie crea que la guarda del nombre basta: §F.17
/// midió que el nombre es **idéntico entre temporadas**.
public struct FederationScorerTable: Equatable, Sendable {
    /// El nombre literal de la competición, para `Competition.requireSameSource`
    /// (`D-84`). Anulable: la FCF no manda sobre.
    public let competitionName: String?

    /// Las filas, **en el orden que publica la fuente**, que es lo único que
    /// hace de ranking: ninguna de las dos federaciones publica campo de puesto
    /// ([Anexo RFFM §F.13], §F.19, [Anexo FCF §C.10.7]).
    ///
    /// **Y ese orden no se convierte en `rank` aquí ni en ningún sitio.** El
    /// *spec* se comprometió a respetar el puesto del proveedor *"porque los
    /// criterios de desempate son suyos"*; numerar nosotros los empates —dos
    /// goleadores con 45 goles en §F.13— sería inventar ese desempate y servirlo
    /// con cara de dato de la fuente.
    public let rows: [FederationScorerRow]

    public init(competitionName: String?, rows: [FederationScorerRow]) {
        self.competitionName = competitionName
        self.rows = rows
    }
}

/// Una fila del ranking publicado.
///
/// # El equipo es una **etiqueta**, no un `FederationTeamRef`, y ahí NO se copia
/// lo que hizo F7
///
/// `FederationStandingRow` reutiliza `FederationTeamRef` porque sus filas hay que
/// **emparejarlas** con un `Team` por la cadena de §3.7. Éstas no se emparejan con
/// nada (`D-09`), así que un `FederationTeamRef` aquí sería una invitación a
/// hacerlo — y el *spec* fija `teamLabel` como **texto** precisamente para que no
/// se haga (`D-32`).
///
/// Hay además un motivo de forma: la RFFM publica el nombre del equipo con la
/// letra **pegada y sin comillas** (`"AULA C.F. - BREZO OSUNA A"`), al revés que
/// en el calendario ([Anexo RFFM §F.13]). Meterlo por `FederationTeamRef`
/// obligaría a partirlo, y partirlo mal es peor que no partirlo: aquí el texto
/// solo se pinta.
///
/// > **Y que no se empareje no es que no se pueda.** §F.19 midió que el
/// > `codigo_equipo` del ranking casa **16/16** con el del calendario. La unión
/// > existiría, por id y sin degradar a nombre. No se hace porque `D-09` no
/// > quiere; por eso ese código **ni se transporta**.
///
/// # Casi todo es opcional, al revés que en `FederationStandingRow`
///
/// Allí los ocho contadores son obligatorios y el parser falla si falta uno,
/// porque **una clasificación es un bloque**: una fila sin posición deja un hueco
/// en una numeración que el *spec* declara imposible. Aquí las filas son
/// **independientes** —no hay numeración que agujerear—, así que un ranking de
/// 217 de 218 sigue siendo un ranking utilizable y tirar la pasada entera por una
/// fila rara sería el error caro de `D-75`. La fila que no se pueda construir se
/// **descarta y se apunta** (`unidentifiedScorer`), que es `D-86` a escala de
/// fila.
public struct FederationScorerRow: Equatable, Sendable {
    /// `codigo_jugador` / `codjugador`: **la clave del *upsert*** (`D-93`).
    ///
    /// Anulable **aquí** aunque sea obligatorio en el Dominio, y no es una
    /// contradicción: este tipo describe *lo que dijo una fuente ajena*, con sus
    /// huecos, y la entidad describe lo que estamos dispuestos a guardar. El
    /// hueco lo convierte en descarte el caso de uso.
    ///
    /// Medido presente y único en **426/426** filas de los tres volcados, así que
    /// el descarte es la red y no el camino.
    public let federationPlayerID: String?

    /// El nombre tal cual lo publica la fuente. No se normaliza: `NormalizedName`
    /// existe para **emparejar**, y aquí no se empareja nada.
    public let fullName: String

    /// El equipo como texto del proveedor, entero y sin partir.
    public let teamLabel: String

    /// Goles. `nil` ⇒ **la fuente no dijo nada**, que no es `0` — la misma
    /// distinción sobre la que `D-56` construye la política de *upsert*.
    ///
    /// En la FCF ojo con de dónde sale: el campo se llama `goles` y hay un
    /// `total` al lado que **no** es el total de goles sino los partidos jugados
    /// (medido 0/50, [Anexo FCF §C.10.7]).
    public let goals: Int?

    /// El puesto **según el proveedor**, y hoy `nil` desde las dos fuentes.
    ///
    /// Se transporta igualmente, y no es el caso de `FederationRound.label`: aquél
    /// tenía productor y **ningún consumidor** —su única línea en el backend era
    /// `self.label = label`—; éste tiene consumidor —`LeagueScorer.rank`, que el
    /// *spec* declara— y ningún productor **todavía**. Quitarlo dejaría muerta la
    /// columna del modelo; dejarlo cuesta un opcional y hace que el día que una
    /// federación lo publique solo haya que tocar su parser.
    public let rank: Int?

    public init(
        federationPlayerID: String?,
        fullName: String,
        teamLabel: String,
        goals: Int?,
        rank: Int? = nil
    ) {
        self.federationPlayerID = federationPlayerID
        self.fullName = fullName
        self.teamLabel = teamLabel
        self.goals = goals
        self.rank = rank
    }
}
