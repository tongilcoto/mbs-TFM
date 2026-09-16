public import struct Foundation.Date

/// La fila de clasificación de un equipo en una jornada (§3.2, entidad 22).
///
/// # Es un *snapshot*, no un acumulado
///
/// La unidad es **(jornada, equipo)**, que es el `UNIQUE` de §3.5: la tabla
/// guarda la foto *tras* cada jornada, no el estado actual. De ahí sale toda la
/// pantalla de clasificación con su columna PREV, y de ahí sale también que la
/// FCF no pueda rellenar hacia atrás (`D-55`): lo que no se capturó esa semana
/// no se recupera.
///
/// # Agnóstica a la fuente, y eso es la decisión (`D-15`)
///
/// La misma fila vale **ingerida** de la federación o **calculada** desde
/// `Match`, y el cliente no distingue: la procedencia se expone una vez por
/// tenant, en `ClubResponse.federationProvidesRoundStandings` (`D-29`, `D-55`).
/// Por eso aquí no hay ninguna marca de origen — sería la columna constante que
/// `D-28` y `D-29` ya rechazaron.
///
/// # Modelo de lectura, no agregado (§4.2, §4.5)
///
/// La escribe el módulo de ingesta por *upsert*, nunca un repositorio de
/// dominio, y no tiene `GET /{id}` (`D-34`). El `id` existe porque toda tabla
/// tiene PK (§3.5).
///
/// # Lo que esta entidad **no** guarda, y es deliberado
///
/// - **`form`**, la racha. El *spec* la publica embebida en cada fila pero se
///   **deriva desde `Match` en el puerto de lectura** (`D-34`): calcularla
///   diferenciando *snapshots* consecutivos exigiría que la cadena esté
///   completa, y en un alta a mitad de temporada no lo está (`D-33`).
/// - **La aritmética.** Ver el `init`.
public struct StandingRow: Identifiable, Equatable, Sendable {
    public let id: StandingRowID
    public let competitionID: CompetitionID

    /// La jornada de la que esto es *snapshot*. La temporada se alcanza por aquí
    /// vía `Competition`, no con un `seasonID` propio (`D-28`).
    public let roundID: RoundID

    public let teamID: TeamID

    /// Posición en esta jornada. Es el **orden fijo** en el que se sirve la
    /// lista: una clasificación desordenada no es una clasificación (§5.1).
    public let position: Int

    /// La columna PREV del mockup. **Se almacena, no se deriva** (`D-33`).
    ///
    /// **Nula** en la primera jornada de la competición y en la primera jornada
    /// ingerida de un alta tardía, y en los dos casos eso es un dato, no un
    /// fallo: el cliente pinta *"–"*. La RFFM **no la publica** ([Anexo RFFM
    /// §F.8]), así que la calcula la ingesta comparando con el *snapshot*
    /// anterior — y cuando no hay anterior, aquí queda `nil`.
    public let previousPosition: Int?

    public let played: Int
    public let won: Int
    public let drawn: Int
    public let lost: Int
    public let goalsFor: Int
    public let goalsAgainst: Int

    /// Puntos (PTS). **No se recalculan desde G/E/P** — ver el `init`.
    public let points: Int

    public let createdAt: Date
    public let updatedAt: Date

    /// Guarda **lo estructural y nada más**, y la frontera es una decisión.
    ///
    /// # Lo que se guarda
    ///
    /// Una posición empieza en 1 y un contador no es negativo. Son las mismas
    /// dos reglas que el *spec* declara (`minimum: 1` y `minimum: 0`) y que el
    /// generador **no** hace cumplir (`D-65`), así que las hace cumplir el
    /// Dominio según la tabla de reparto de §5.5.
    ///
    /// # Lo que **no** se guarda, y por qué
    ///
    /// Ni `points == 3·won + drawn` ni `played == won + drawn + lost`. No es un
    /// olvido: es que **la aritmética de la tabla es del que organiza la liga**,
    /// y tenemos las dos pruebas delante.
    ///
    /// - El *spec* ya se comprometió en `points`: *"no se recalcula en el BFF a
    ///   partir de G/E/P: si la federación publica la clasificación, el dato
    ///   bueno es el suyo — los sistemas de puntuación y las sanciones con
    ///   descuento de puntos no siempre se deducen de la tabla"*. La RFFM
    ///   publica `puntos_sancion` ([Anexo RFFM §F.8]), así que la tabla oficial
    ///   de un grupo con una sanción **no cumple** la identidad.
    /// - Y `played` tampoco cuadra con la jornada: en la muestra de §F.8, dentro
    ///   de la **misma** jornada 9, `jugados` vale 8 en nueve equipos y 9 en
    ///   cuatro. La clasificación *"a jornada N"* cuenta partidos **realmente
    ///   disputados**.
    ///
    /// El criterio de fondo es el de `D-75` aplicado a la fila entera: los dos
    /// errores no cuestan lo mismo. Una invariante aritmética de más convierte
    /// *"la federación hace cuentas que no controlamos"* en una excepción que
    /// tira **la clasificación entera de la jornada**; una de menos deja pasar
    /// una fila rara que la pasada siguiente reescribe, porque la RFFM sirve la
    /// jornada pasada las veces que haga falta (`D-55`).
    ///
    /// > Ojo al tocarlo: el *fallback* calculado (`StandingTable`) **sí** cumple
    /// > las dos identidades, porque las construye él. Que las cumpla una de las
    /// > dos fuentes no es motivo para exigírselas a la otra.
    public init(
        id: StandingRowID,
        competitionID: CompetitionID,
        roundID: RoundID,
        teamID: TeamID,
        position: Int,
        previousPosition: Int? = nil,
        played: Int,
        won: Int,
        drawn: Int,
        lost: Int,
        goalsFor: Int,
        goalsAgainst: Int,
        points: Int,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        guard position >= 1 else {
            throw DomainError.invalidValue(
                field: "position", reason: "la clasificación se numera desde 1")
        }
        if let previousPosition, previousPosition < 1 {
            throw DomainError.invalidValue(
                field: "previousPosition", reason: "la clasificación se numera desde 1")
        }
        for (field, value) in [
            ("played", played), ("won", won), ("drawn", drawn), ("lost", lost),
            ("goalsFor", goalsFor), ("goalsAgainst", goalsAgainst), ("points", points),
        ] {
            guard value >= 0 else {
                throw DomainError.invalidValue(field: field, reason: "no puede ser negativo")
            }
        }

        self.id = id
        self.competitionID = competitionID
        self.roundID = roundID
        self.teamID = teamID
        self.position = position
        self.previousPosition = previousPosition
        self.played = played
        self.won = won
        self.drawn = drawn
        self.lost = lost
        self.goalsFor = goalsFor
        self.goalsAgainst = goalsAgainst
        self.points = points
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// GF − GC.
    ///
    /// **Se deriva y no se guarda**: es la resta de dos columnas que ya están, y
    /// el *spec* no la publica (§5.1) porque el cliente la hace solo. Existe
    /// porque el orden del *fallback* calculado la necesita (`D-15`), y ahí sí
    /// es una regla del Dominio.
    public var goalDifference: Int { goalsFor - goalsAgainst }
}
