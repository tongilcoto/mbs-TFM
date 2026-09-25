public import Domain
public import struct Foundation.Date

/// Puerto de salida de `Round` (§4.3).
///
/// **Sin `delete` y sin `find`**, como los de F1: la ingesta no borra jornadas
/// —lo que la fuente deja de publicar no se destruye (`D-75`)— y no busca una
/// suelta, porque carga las de la competición entera para emparejar.
public protocol RoundRepository: Sendable {
    /// Todas las jornadas de la competición. Es la lista contra la que la pasada
    /// decide crear o actualizar.
    func list(competitionID: CompetitionID) async throws -> [Round]

    /// *Upsert* por `id` (§4.3). El id lo pone el caso de uso, no la base:
    /// así la fila recién creada puede entrar en los candidatos de la misma
    /// pasada sin releerla.
    func save(_ round: Round) async throws
}

/// Puerto de salida de `OpponentClub` (§4.3).
public protocol OpponentClubRepository: Sendable {
    /// **Todos los del tenant, sin filtro de competición**, y es deliberado: un
    /// club rival es identidad de club y **no lleva temporada ni competición**
    /// (§3.2, `D-28`). El mismo "C.D. Galapagar" que juega en cadete es el que
    /// juega en juvenil, y emparejarlo solo contra los de esta competición
    /// crearía un duplicado por categoría.
    func list() async throws -> [OpponentClub]

    func save(_ club: OpponentClub) async throws
}

/// Puerto de salida de `Team` (§4.3).
public protocol TeamRepository: Sendable {
    /// **Todos los del tenant**, por el mismo motivo que los clubes: `Team`
    /// tampoco lleva temporada (`D-28`). Incluye los **propios**, que el paso 1
    /// de la cadena sí tiene que poder reconocer si ya están enganchados
    /// (`D-67`).
    func list() async throws -> [Team]

    /// **Uno por su id**, que es lo que estrena F10 (`C-D.1`).
    ///
    /// Hasta aquí este puerto solo sabía servir la lista entera, y era
    /// suficiente: la ingesta carga todos los candidatos para emparejar (§3.7) y
    /// nadie llegaba a un equipo **por su id**. El enganche sí — la ruta es
    /// `/v1/teams/{id}/federation-link` (`D-67`), así que el equipo llega
    /// designado desde fuera y lo primero que hay que poder decir es *"ése no
    /// existe"* (**404**, `C-E.6`).
    ///
    /// Filtrar `list()` en el caso de uso habría dado la misma respuesta
    /// trayéndose el tenant entero para descartarlo, y habría dejado la decisión
    /// de *"no está"* repartida entre dos capas.
    func find(_ id: TeamID) async throws -> Team?

    func save(_ team: Team) async throws
}

/// Puerto de salida de `TeamRegistration` (`D-68`, §4.3).
///
/// # Por qué la consulta es por la pareja y no por la terna
///
/// Porque **la terna es lo que se decide**, no lo que se busca. La cascada del
/// enganche tiene que distinguir tres situaciones sobre el mismo `(equipo,
/// temporada)`: que ya esté inscrito **en esta competición** —no hay nada que
/// hacer—, que exista la fila **con competición nula** —la de junio, que se
/// *completa*— o que no haya ninguna. Preguntando por la terna entera, los dos
/// últimos casos llegan indistinguibles como `nil` y el enganche añadiría una
/// segunda fila al equipo que el club ya había inscrito.
///
/// # Y por qué no hay `delete`
///
/// Por lo mismo que sus vecinas (`D-75`): lo que se escribió no se destruye. Dar
/// de baja una inscripción es del backoffice, que no tiene fase.
public protocol TeamRegistrationRepository: Sendable {
    /// Las inscripciones de **ese equipo en esa temporada**. Son pocas por
    /// definición —liga y copa (`D-12`)— y el `UNIQUE` de tres columnas con
    /// `NULLS NOT DISTINCT` (`C-D.3`) garantiza que no se repitan.
    func list(teamID: TeamID, seasonID: SeasonID) async throws -> [TeamRegistration]

    /// *Upsert* por `id`, igual que los demás: el id lo pone el caso de uso.
    /// **Completar la fila de junio es un `save` con el mismo `id`**, no una
    /// fila nueva.
    func save(_ registration: TeamRegistration) async throws
}

/// Puerto de salida de `Match` (§4.3).
public protocol MatchRepository: Sendable {
    func list(competitionID: CompetitionID) async throws -> [Match]

    func save(_ match: Match) async throws
}

/// Puerto de salida de `IngestionRun` (§4.3): **el registro de las pasadas**.
///
/// # Es el único de F5 con un ciclo de vida propio
///
/// Los otros cuatro se usan **dentro** del ámbito de la pasada. Éste no puede:
/// la pasada es una transacción (`D-83`), así que un registro escrito dentro de
/// ella se desharía con el `rollback` **justo en el caso que más importa** — la
/// pasada que falla, que es la que nadie ve porque no hay usuario delante
/// (§2.3-b). Se escribe en su propio ámbito, después, gane o pierda (`D-85`).
public protocol IngestionRunRepository: Sendable {
    /// Escribe el registro, **por `id`**.
    ///
    /// # Decía "solo inserta", y F10-bis lo enmienda con su argumento
    ///
    /// El texto era: *"una pasada ocurrió o no ocurrió, y reescribir la historia
    /// de una sincronización no significa nada"*. Era bueno **mientras toda fila
    /// naciera acabada**. [D-96] crea la excepción y la crea entera: una fila
    /// `accepted` dice *"todavía no ha ocurrido"*, así que cerrarla no reescribe
    /// ninguna historia — **la termina**.
    ///
    /// Escribir el resultado como fila nueva dejaría **dos versiones de la misma
    /// pasada**, una eternamente abierta y el cliente siguiendo la suya sin
    /// enterarse de que ya hay resultado: el desenlace que
    /// `IngestionRun.closed(as:at:)` describe como el peor posible.
    ///
    /// Lo que **no** cambia es que una pasada acabada no se retoca: lo impide el
    /// Dominio, que solo deja cerrar lo que está abierto (`C-A.6`).
    func record(_ run: IngestionRun) async throws

    /// Las últimas pasadas de una competición, **de la más reciente a la más
    /// antigua**, que es el orden en el que se leen: la pregunta es *"¿qué pasó
    /// la última vez?"*.
    func list(competitionID: CompetitionID, limit: Int) async throws -> [IngestionRun]

    /// **La pasada que está pedida y todavía no ha corrido**, si la hay
    /// ([D-96], F10-bis).
    ///
    /// Es lo que permite que la pasada **adopte** en vez de abrir otra fila. Va
    /// por `kind` porque el `202` promete una cosa concreta —el calendario— y las
    /// de clasificación y goleadores que vengan detrás son suyas, no lo que
    /// alguien pidió.
    ///
    /// # Por qué es su propia consulta y no un filtro sobre `list`
    ///
    /// Porque `list` está paginada por definición —*"las últimas N"*— y una fila
    /// aceptada que se quedó abierta hace tres semanas **no está en las últimas
    /// N**. Buscarla con un `limit` sería fijar un número que nada justifica y
    /// fallar en silencio justo en el caso que esto viene a arreglar: el de la
    /// pasada que nadie cerró.
    func findAccepted(
        competitionID: CompetitionID, kind: IngestionKind
    ) async throws -> IngestionRun?
}

/// Puerto de salida de `StandingRow` (§4.3, F7).
///
/// # Dos operaciones, y la segunda es la que no se ve venir
///
/// `save` es el *upsert* de siempre. `list(roundID:)` está porque **la columna
/// PREV se calcula comparando con la jornada anterior** (`D-33`): sin poder leer
/// ese *snapshot*, la pasada no tiene con qué rellenarla y la pantalla pintaría
/// *"–"* en toda la temporada.
///
/// # Por qué se lee por jornada y no por competición
///
/// Porque la unidad del modelo es **(jornada, equipo)** y la pregunta que se le
/// hace es siempre *"¿cómo estaba la tabla tras la jornada N?"* — la de la
/// pantalla y la de PREV son la misma. Traerse la competición entera serían 30
/// jornadas × 16 equipos para usar 16 filas.
///
/// # Y no hay `delete`
///
/// Por lo mismo que en el resto de la salida de la ingesta (`D-75`): lo que la
/// fuente deja de publicar no se destruye. Una fila que sobra —un equipo
/// retirado a mitad de liga— deja de aparecer en las jornadas siguientes porque
/// la fuente ya no la manda, no porque alguien la borre.
public protocol StandingRowRepository: Sendable {
    /// La tabla de una jornada, **ordenada por posición**: una clasificación
    /// desordenada no es una clasificación (§5.1).
    func list(roundID: RoundID) async throws -> [StandingRow]

    /// *Upsert* por `id`, igual que sus hermanas de F5: el id lo pone el caso de
    /// uso para que la fila recién escrita entre en los candidatos de la misma
    /// pasada sin releerla.
    func save(_ row: StandingRow) async throws
}

/// Puerto de salida de `LeagueScorer` (§4.3, F8).
///
/// # Tres operaciones, y la tercera **no la tiene ningún otro puerto de ingesta**
///
/// `list` y `save` son lo de siempre. **`retire` borra**, y es la excepción del
/// modelo: `D-75` dice que lo que la fuente deja de publicar no se destruye, y
/// por eso `StandingRowRepository`, `MatchRepository` y `RoundRepository` no
/// tienen `delete`.
///
/// La condición que autoriza la excepción es **"la tabla es estado vigente y no
/// histórico"** (`D-94`), y en toda la salida de la ingesta solo la cumple ésta:
/// una fila de clasificación es la foto de una jornada que ya pasó y sigue siendo
/// verdad; un ranking de goleadores dice *"cómo va la cosa ahora"*, y un goleador
/// que el proveedor dejó de publicar no es un dato viejo identificable — es una
/// fila indistinguible de las buenas dentro de una tabla que afirma ser la de
/// hoy.
///
/// > **Al añadir la séptima salida de la ingesta: si tiene jornada, es histórico
/// > y no se borra.**
///
/// # Por qué se lee por competición y no hay `find`
///
/// Porque la unidad de consumo es **la tabla entera de una competición** —el
/// ranking—, igual que en la clasificación es la de una jornada. Y no hay acceso
/// por id (`D-34`): el `id` existe porque toda tabla tiene PK (§3.5).
public protocol LeagueScorerRepository: Sendable {
    /// El ranking de una competición, **en su orden** (`D-49`, §5.1): puesto
    /// ascendente con los nulos al final, goles descendente como criterio real y
    /// el nombre como desempate estable.
    ///
    /// **Hoy el puesto es nulo siempre** —ninguna de las dos federaciones lo
    /// publica—, así que en la práctica ordena por goles y nombre. El orden se
    /// escribe entero igualmente: el día que una fuente lo publique, `D-49` dice
    /// que se respeta el suyo, y esa regla no puede vivir en el llamante.
    func list(competitionID: CompetitionID) async throws -> [LeagueScorer]

    /// *Upsert* por `id`, igual que sus hermanas: el id lo pone el caso de uso
    /// para que la fila recién escrita entre en los candidatos de la misma pasada
    /// sin releerla.
    func save(_ scorer: LeagueScorer) async throws

    /// **Retira los que el proveedor dejó de publicar** (`D-94`): borra las filas
    /// de **esta competición** que no lleven la marca de esta pasada.
    ///
    /// Devuelve cuántas borró, porque ese número va al registro (`D-85`) y es el
    /// que delata una pasada que en vez de limpiar ha vaciado.
    ///
    /// # Las dos mitades del filtro son igual de obligatorias
    ///
    /// Sin `keepingMark` esto vacía la competición. **Y sin `competitionID` esto
    /// vacía el club entero** — que es la clase de fallo que no da error, se lleva
    /// los datos y solo se nota al mirar la pantalla equivocada. Van juntas en la
    /// firma para que no se pueda llamar con una sola.
    ///
    /// # Es "distinto de", no "anterior a", y eso lo enseñó un test
    ///
    /// La primera versión era `syncedBefore:` con un `<`, que se lee igual de bien
    /// y **es frágil**: hace depender la regla de la resolución del reloj. Dos
    /// pasadas que cayeran en el mismo instante —un reintento rápido, un reloj con
    /// poca resolución— no retirarían nada, porque lo viejo tendría exactamente la
    /// misma marca que lo nuevo. Lo destapó el test de la retirada con
    /// `TickingClock`, cuya primera lectura es el instante de partida.
    ///
    /// Lo que se quiere decir no es *"lo anterior"* sino **"lo que esta pasada no
    /// ha tocado"**, y eso se expresa exacto: marca distinta de la mía. Incluye
    /// las filas **sin marca**, que son las que ninguna pasada ha confirmado —
    /// dejarlas fuera las haría inmortales.
    ///
    /// # Y por qué la marca y no la resta de conjuntos
    ///
    /// Comparar *"lo que había"* contra *"lo que vino"* en memoria da el mismo
    /// resultado y obliga a releer la tabla entera. La marca lo resuelve en el
    /// `WHERE`, y sobre todo **es correcta si la pasada se interrumpe**: todo
    /// ocurre dentro de la transacción de `D-83`, así que o se escriben las nuevas
    /// y se retiran las viejas, o no pasa ninguna de las dos cosas. Con la
    /// variante ingenua —*"borro todo y vuelvo a insertar"*— una caída a mitad
    /// dejaría la tabla vacía; aquí eso no es representable.
    @discardableResult
    func retire(competitionID: CompetitionID, keepingMark: Date) async throws -> Int
}
