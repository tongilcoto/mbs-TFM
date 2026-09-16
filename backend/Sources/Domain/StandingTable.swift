import struct Foundation.UUID

/// El ***fallback* calculado** de la clasificación (`D-15`): la tabla de una
/// jornada, deducida de los partidos.
///
/// # Por qué es cálculo y no un formulario
///
/// `D-15` lo decidió por una razón de propiedad, no de comodidad: si el hueco se
/// tapara escribiendo la clasificación a mano en el backoffice, `StandingRow`
/// tendría **dos escritores** y sería la única casilla con dos dueños de toda la
/// matriz de §5.1 — justo lo que `D-21` rechaza. Calculándola, el único escritor
/// sigue siendo el módulo de ingesta.
///
/// # Cuándo se dispara, que ya no es lo que `D-15` escribió (`D-55`)
///
/// No es *"la federación no publica clasificación"* —se midió y **las dos la
/// publican**— sino **"esta jornada es anterior a nuestra primera
/// sincronización"**. Con la FCF, que solo sirve la vigente, todo lo anterior al
/// alta se calcula y en régimen estacionario ya no hace falta; con la RFFM, que
/// la sirve histórica, casi nunca hace falta. El cálculo es el mismo.
///
/// # Lo que no puede dar, asumido por escrito
///
/// Sin desempate por **enfrentamiento directo** y sin **sanciones
/// administrativas** (`D-55`). Es peor dato que el oficial; es el único posible
/// para el histórico previo al alta, y por eso la procedencia **no** viaja en la
/// fila (`D-29`): lo que el cliente necesita saber es la capacidad de su
/// federación, una vez, no el origen de cada una de veinte filas.
///
/// # Es `Domain` y no `Application` a propósito
///
/// No toca puertos, no hace I/O y es la clase de regla que más caro sale
/// equivocar en silencio — el mismo sitio en el que viven `UpsertPolicy` (F3) y
/// `MatchingChain` (F4), y por el mismo motivo: se prueba con cero
/// infraestructura.
public enum StandingTable {

    /// Un partido **visto por la clasificación**: quién, contra quién, en qué
    /// jornada y con qué marcador.
    ///
    /// No es `Match` —le sobran `venue`, `status`, `kickoff` y los tres ids— y
    /// tampoco es el DTO de una fuente: es lo poco que la aritmética necesita.
    /// Que sea un tipo propio es lo que permite probar la tabla sin construir
    /// veinte `Match` con sus `Kickoff` y sus fechas.
    public struct Fixture: Equatable, Sendable {
        /// **El número, no el `RoundID`.** La tabla corta por jornada y comparar
        /// ids no ordena; traducir id → número es del llamante, que ya tiene las
        /// jornadas cargadas.
        public let roundNumber: Int

        public let homeTeamID: TeamID
        public let awayTeamID: TeamID

        /// `nil` ⇒ **no se ha jugado** (`D-56`). No es `0-0`, y confundirlos
        /// regalaría un punto a cada equipo de cada partido futuro del
        /// calendario.
        public let result: MatchResult?

        public init(
            roundNumber: Int, homeTeamID: TeamID, awayTeamID: TeamID, result: MatchResult?
        ) {
            self.roundNumber = roundNumber
            self.homeTeamID = homeTeamID
            self.awayTeamID = awayTeamID
            self.result = result
        }
    }

    /// Una fila de la tabla calculada, **sin identidad todavía**.
    ///
    /// Le faltan `id`, `competitionID`, `roundID`, `previousPosition` y las
    /// marcas de tiempo, que son cosa de quien la persiste. La separación es la
    /// misma que hay entre `MatchOutcome` y `Match` (F4): el Dominio decide
    /// **qué dice** la fila, el caso de uso decide **qué fila es**.
    public struct Line: Equatable, Sendable {
        public let teamID: TeamID
        public let position: Int
        public let played: Int
        public let won: Int
        public let drawn: Int
        public let lost: Int
        public let goalsFor: Int
        public let goalsAgainst: Int
        public let points: Int

        /// La columna PREV. Nace **nula** —`upTo` hace aritmética, no historia—
        /// y la resuelve `resolvingPreviousPositions` cuando hay jornada
        /// anterior con la que comparar (`D-33`).
        public let previousPosition: Int?

        public init(
            teamID: TeamID,
            position: Int,
            played: Int,
            won: Int,
            drawn: Int,
            lost: Int,
            goalsFor: Int,
            goalsAgainst: Int,
            points: Int,
            previousPosition: Int? = nil
        ) {
            self.teamID = teamID
            self.position = position
            self.played = played
            self.won = won
            self.drawn = drawn
            self.lost = lost
            self.goalsFor = goalsFor
            self.goalsAgainst = goalsAgainst
            self.points = points
            self.previousPosition = previousPosition
        }

        public var goalDifference: Int { goalsFor - goalsAgainst }

        /// La misma fila con su columna PREV puesta.
        func withPreviousPosition(_ previousPosition: Int?) -> Line {
            Line(
                teamID: teamID, position: position,
                played: played, won: won, drawn: drawn, lost: lost,
                goalsFor: goalsFor, goalsAgainst: goalsAgainst, points: points,
                previousPosition: previousPosition)
        }
    }

    /// Puntos por victoria y por empate.
    ///
    /// Van como constantes con nombre y no como `3` y `1` sueltos dentro de la
    /// suma porque son **la regla de la competición**, no una constante mágica:
    /// el día que haga falta una competición con otro sistema, esto es lo que se
    /// parametriza. Hoy no hace falta, y `D-15` no lo pide.
    static let pointsPerWin = 3
    static let pointsPerDraw = 1

    /// La clasificación **tras** la jornada `cutoff`.
    ///
    /// # Los dos usos de `fixtures`, que no son el mismo
    ///
    /// La lista es **el calendario entero de la competición**, no los partidos
    /// jugados, y se usa para dos cosas distintas a propósito:
    ///
    /// - **la plantilla de la tabla** sale de *todos* los partidos, incluidos los
    ///   de jornadas futuras — así la clasificación de la jornada 1 tiene a los
    ///   16 equipos del grupo y no solo a los que ya jugaron;
    /// - **la aritmética** solo cuenta los de `roundNumber <= cutoff` **con
    ///   marcador**.
    ///
    /// # El corte es lo que la hace un *snapshot*
    ///
    /// Sin él, recalcular el histórico daría treinta veces la tabla final y
    /// `previousPosition` no significaría nada (`D-33`).
    ///
    /// # El orden, y el criterio que no existe
    ///
    /// Puntos ↓, diferencia de goles ↓, goles a favor ↓. El cuarto criterio del
    /// reglamento —**el enfrentamiento directo**— `D-55` lo deja fuera, así que
    /// dos equipos iguales en los tres están de verdad empatados y cualquier
    /// orden es igual de malo deportivamente.
    ///
    /// **Lo que sí importa es que no baile**: la tabla se guarda como *snapshot*
    /// y `previousPosition` se calcula comparándola con la de la jornada
    /// anterior, así que un orden que dependa de cómo devolvió las filas la base
    /// **inventa subidas y bajadas que no ocurrieron**. Por eso el último
    /// criterio es el `id` del equipo: arbitrario, sí, pero **estable**, y no
    /// depende del llamante. Un `sorted` estable sobre el orden de entrada no
    /// bastaría — trasladaría el problema a quien construye la lista, y
    /// `Array.sorted` tampoco promete estabilidad.
    public static func upTo(round cutoff: Int, fixtures: [Fixture]) -> [Line] {
        var tallies: [TeamID: Tally] = [:]
        // **El orden de entrada al `sorted`, y no es cosmético.** La primera
        // versión ordenaba el `Dictionary` directamente, y el recorrido de un
        // diccionario de Swift depende del `hash` **y del proceso**: el mismo
        // programa, con los mismos datos, podía dar dos tablas distintas en dos
        // ejecuciones en cuanto dos equipos empataran a todo. Lo destapó una
        // mutación —quitar el desempate final **sobrevivía**, porque el orden
        // que quedaba no era el de nadie— y no un rojo.
        var appearance: [TeamID] = []

        for fixture in fixtures {
            // La plantilla primero, y **antes** del corte: un equipo que solo
            // aparece en jornadas futuras sigue estando en el grupo.
            for team in [fixture.homeTeamID, fixture.awayTeamID] where tallies[team] == nil {
                tallies[team] = Tally()
                appearance.append(team)
            }

            guard fixture.roundNumber <= cutoff, let result = fixture.result else { continue }
            tallies[fixture.homeTeamID]?.add(scored: result.homeScore, conceded: result.awayScore)
            tallies[fixture.awayTeamID]?.add(scored: result.awayScore, conceded: result.homeScore)
        }

        return appearance
            .compactMap { team in tallies[team].map { (team: team, tally: $0) } }
            .sorted { lhs, rhs in
                let (a, b) = (lhs.tally, rhs.tally)
                if a.points != b.points { return a.points > b.points }
                if a.goalDifference != b.goalDifference {
                    return a.goalDifference > b.goalDifference
                }
                if a.goalsFor != b.goalsFor { return a.goalsFor > b.goalsFor }
                return lhs.team.raw.uuidString < rhs.team.raw.uuidString
            }
            .enumerated()
            .map { index, entry in
                Line(
                    teamID: entry.team,
                    position: index + 1,
                    played: entry.tally.played,
                    won: entry.tally.won,
                    drawn: entry.tally.drawn,
                    lost: entry.tally.lost,
                    goalsFor: entry.tally.goalsFor,
                    goalsAgainst: entry.tally.goalsAgainst,
                    points: entry.tally.points)
            }
    }

    /// Las mismas líneas, **con su columna PREV puesta** (`D-33`).
    ///
    /// # Por qué existe si el *spec* dice que PREV «se almacena, no se deriva»
    ///
    /// Porque las dos cosas son ciertas y hablan de momentos distintos. **Ninguna
    /// de las dos federaciones publica la posición anterior** ([Anexo RFFM §F.8]),
    /// así que hay que calcularla comparando con el *snapshot* de antes. Lo que
    /// `D-33` prohíbe es hacerlo **al leer** —diferenciando tablas consecutivas
    /// cuando alguien pide la clasificación—, porque eso se cae justo en el caso
    /// real: un club que da de alta la competición a mitad de temporada no tiene
    /// la jornada anterior de la que leerla. Se calcula **una vez, al ingerir**,
    /// y se guarda.
    ///
    /// # Una sola puerta para las dos fuentes (`D-15`)
    ///
    /// Vive aquí y no en el adaptador de la RFFM porque la fila es **agnóstica a
    /// la fuente**: la tabla ingerida y la calculada son las mismas `Line`. Si
    /// esto viviera en el adaptador, el *fallback* calculado se quedaría sin
    /// columna PREV — y son justo las jornadas anteriores al alta, que es donde
    /// `D-55` dice que el cálculo se usa.
    ///
    /// # `previous` es la jornada **inmediatamente** anterior, o nada
    ///
    /// Pasar `nil` significa *"no hay jornada N−1"*, y entonces PREV es nula en
    /// toda la tabla: primera jornada de la competición, o primera ingerida de un
    /// alta tardía. Lo que el llamante **no** debe hacer es pasar *"el último
    /// *snapshot* que haya"*: comparar la jornada 21 con la 18 porque las dos de
    /// en medio fallaron pintaría en la columna PREV un movimiento de tres
    /// semanas con cara de ser de una.
    ///
    /// Y un equipo que no estuviera en la anterior tampoco tiene PREV: es `nil`
    /// por ausencia, no por cero.
    public static func resolvingPreviousPositions(
        _ lines: [Line], previous: [Line]?
    ) -> [Line] {
        guard let previous else { return lines.map { $0.withPreviousPosition(nil) } }
        let positions = Dictionary(
            previous.map { ($0.teamID, $0.position) }, uniquingKeysWith: { first, _ in first })
        // **No reordena.** El orden lo decidió quien construyó la tabla —`upTo` o
        // el adaptador—, y dos sitios decidiendo el orden es uno de más.
        return lines.map { $0.withPreviousPosition(positions[$0.teamID]) }
    }

    /// El acumulador de un equipo mientras se recorre el calendario.
    ///
    /// Es privado y mutable a propósito: la alternativa —reducir a `Line`s
    /// inmutables partido a partido— recrearía nueve campos por cada uno de los
    /// 240 partidos de una temporada para no ganar nada, porque esto no sale de
    /// la función.
    private struct Tally {
        var played = 0, won = 0, drawn = 0, lost = 0
        var goalsFor = 0, goalsAgainst = 0

        mutating func add(scored: Int, conceded: Int) {
            played += 1
            goalsFor += scored
            goalsAgainst += conceded
            if scored > conceded {
                won += 1
            } else if scored == conceded {
                drawn += 1
            } else {
                lost += 1
            }
        }

        var goalDifference: Int { goalsFor - goalsAgainst }
        var points: Int { won * StandingTable.pointsPerWin + drawn * StandingTable.pointsPerDraw }
    }
}
