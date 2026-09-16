public import struct Foundation.Date

/// Una fila del ranking de goleadores de la competición (§3.2, entidad 23).
///
/// # Se ingiere y **no se calcula** (`D-09`)
///
/// Es la decisión que define esta entidad. El ranking de la liga incluye a los
/// jugadores **rivales**, de los que no tenemos plantilla y no la vamos a tener:
/// modelar los *rosters* de los rivales se descartó por coste desproporcionado y
/// por datos que nadie iba a teclear. Así que `full_name` y `team_label` son
/// **texto del proveedor**, no claves, y esta fila **no se liga a `Player` ni a
/// `Team`**.
///
/// # Y por eso es la única sin *fallback*, que es lo que la separa de la
/// clasificación (`D-48`)
///
/// `StandingRow` y ésta se parecen tanto —las dos son modelos de lectura, las dos
/// las escribe solo la ingesta, las dos vienen de la misma API— que tratarlas
/// igual es el error fácil. La diferencia es que una clasificación **siempre se
/// puede calcular** desde los `Match` con marcador (`D-15`), y un ranking de
/// goleadores **no**: calcularlo desde `Goal` daría el ranking de nuestra
/// plantilla presentado como ranking de la liga, que es peor que no tener
/// ranking. De ahí que la capacidad `federationProvidesScorers` **no la puedan
/// ignorar las apps**: con `false`, este recurso está vacío para siempre.
///
/// # Estado vigente único, no *snapshot* por jornada
///
/// La otra asimetría con `StandingRow`. No hay `round_id`, no hay columna PREV y
/// no hay histórico: el *upsert* pisa la fila en cada sincronización. De ahí
/// salen las dos decisiones de F8 —la clave con la que se pisa (`D-93`) y la
/// retirada de lo que el proveedor deja de publicar (`D-94`)—, y de ahí sale que
/// la pasada de goleadores caiga del lado **nulo** de `IngestionRun.roundID`.
public struct LeagueScorer: Identifiable, Equatable, Sendable {
    public let id: LeagueScorerID

    /// La competición del ranking. La temporada se alcanza por aquí, no con un
    /// `seasonID` propio (`D-28`).
    public let competitionID: CompetitionID

    /// **El identificador del jugador en la federación, y la clave del *upsert***
    /// (`D-93`).
    ///
    /// `codigo_jugador` en la RFFM, `codjugador` en la FCF. Es **obligatorio**, y
    /// ésa es la asimetría deliberada con sus tres hermanas del modelo:
    /// `federation_team_id` es anulable porque un equipo vive sin él desde que lo
    /// crea el club hasta que se engancha (`D-66`, `D-67`), y
    /// `federation_match_id` porque el proveedor puede no publicarlo (`D-31`).
    /// Una fila de esta tabla **no tiene ese estado intermedio**: la escribe la
    /// ingesta o no existe —no hay `POST` (`D-21`)—, así que una sin
    /// identificador sería una fila que nadie puede volver a encontrar y que el
    /// *upsert* duplicaría cada semana.
    ///
    /// **Texto opaco, no número.** Los códigos de la RFFM no tienen longitud fija
    /// ([Anexo RFFM §F.3]) y los de la FCF tampoco; convertirlos a `Int` para
    /// "normalizarlos" sería inventarles una forma que la fuente no promete.
    public let federationPlayerID: String

    /// El nombre **tal y como lo publica el proveedor** (`"APELLIDOS, NOMBRE"`).
    /// Texto libre, sin normalizar, y **sin garantía de unicidad**: el *spec* lo
    /// dice en la descripción del `id` —*"dos jugadores pueden llamarse igual"*—,
    /// y es el argumento entero de `D-93`.
    public let fullName: String

    /// El equipo **como etiqueta**, no como `TeamRef` (`D-32`).
    ///
    /// Puede llegar de otra categoría o escrito de otra forma, y la RFFM lo
    /// publica con la letra **pegada sin comillas** (`"AULA C.F. - BREZO OSUNA
    /// A"`), al revés que el calendario ([Anexo RFFM §F.13]) — así que ni
    /// siquiera se parte. Sin escudo, por tanto.
    ///
    /// > **Que no se empareje no significa que no se pudiera.** [Anexo RFFM §F.19]
    /// > midió que el `codigo_equipo` del ranking casa **16/16** con el del
    /// > calendario, así que la unión por id existiría. No se hace porque `D-09`
    /// > no quiere, no porque falte el dato — y quien reabra la decisión tiene que
    /// > discutir eso y no la imposibilidad.
    public let teamLabel: String

    /// Goles acumulados en la competición, según el proveedor.
    public let goals: Int

    /// Posición en el ranking **según el proveedor**, y anulable.
    ///
    /// **No era una precaución teórica: ninguna de las dos federaciones lo
    /// publica** ([Anexo RFFM §F.13], §F.19, [Anexo FCF §C.10.7]). Las listas
    /// llegan ordenadas por goles descendente y sin numerar, así que hoy esto es
    /// `nil` siempre.
    ///
    /// **Y la ingesta no lo sintetiza desde el índice del array**, que es lo
    /// tentador. El *spec* se comprometió a **respetar el del proveedor** cuando
    /// lo haya *"porque los criterios de desempate son suyos y no los
    /// conocemos"*; numerar nosotros los empates —dos goleadores con 45 goles en
    /// la muestra de §F.13— sería justo inventarse ese desempate y presentarlo
    /// como dato de la fuente.
    public let rank: Int?

    /// **La marca del *upsert*** (`D-94`), y con ella la retirada.
    ///
    /// Cada pasada la escribe con su instante en las filas que sí vinieron; las
    /// de esa competición que se quedan atrás son las que el proveedor dejó de
    /// publicar, y se borran. Es la única tabla de la salida de la ingesta que lo
    /// hace, porque es la única que es **estado vigente y no histórico**.
    ///
    /// **No viaja en el DTO** (`D-29`): sería la columna constante —el mismo
    /// instante repetido en doscientas filas— y la pregunta que respondería ya la
    /// responde `CompetitionResponse.lastSyncedAt`, que es la granularidad buena.
    ///
    /// Anulable porque la entidad se puede construir antes de escribirse; quien
    /// la pone es la pasada, no el `init`.
    public let syncedAt: Date?

    public let createdAt: Date
    public let updatedAt: Date

    /// Guarda **lo estructural**, con el mismo criterio que `StandingRow` y por
    /// la misma razón (`D-75`).
    ///
    /// Lo que se exige: que la clave del *upsert* exista, que los dos textos que
    /// la pantalla pinta no estén vacíos, que los goles no sean negativos y que
    /// el puesto —si viene— empiece en 1. Son las reglas que el *spec* declara
    /// (`minimum: 0`, `minimum: 1`) y que el generador **no** hace cumplir
    /// (`D-65`).
    ///
    /// Lo que **no** se exige, y es deliberado: ninguna aritmética. No hay nada
    /// contra lo que cuadrar estos goles —son de jugadores ajenos, y `Goal` solo
    /// cubre los partidos del club (§3.7)—, así que una comprobación cruzada
    /// tiraría la pasada entera por un dato que no controlamos. Y **cero goles es
    /// una fila válida**: nada impide que un proveedor publique a quien aún no ha
    /// marcado.
    public init(
        id: LeagueScorerID,
        competitionID: CompetitionID,
        federationPlayerID: String,
        fullName: String,
        teamLabel: String,
        goals: Int,
        rank: Int? = nil,
        syncedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        // Va primero porque es la clave: sin ella la fila no es identificable, y
        // las demás guardas hablarían de una fila que no se puede volver a
        // encontrar.
        guard !federationPlayerID.trimmed.isEmpty else {
            throw DomainError.invalidValue(
                field: "federationPlayerID",
                reason: "es la clave con la que se reconoce la fila en la pasada siguiente")
        }
        guard !fullName.trimmed.isEmpty else {
            throw DomainError.invalidValue(field: "fullName", reason: "no puede estar vacío")
        }
        guard !teamLabel.trimmed.isEmpty else {
            throw DomainError.invalidValue(field: "teamLabel", reason: "no puede estar vacío")
        }
        guard goals >= 0 else {
            throw DomainError.invalidValue(field: "goals", reason: "no puede ser negativo")
        }
        if let rank, rank < 1 {
            throw DomainError.invalidValue(
                field: "rank", reason: "el ranking se numera desde 1")
        }

        self.id = id
        self.competitionID = competitionID
        self.federationPlayerID = federationPlayerID
        self.fullName = fullName
        self.teamLabel = teamLabel
        self.goals = goals
        self.rank = rank
        self.syncedAt = syncedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
