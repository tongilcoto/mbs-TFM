import Application
import Domain
import Foundation
import Testing

@testable import Federation

/// **El canario** (Plan §4.4). Fuera de la batería normal, tras
/// `FEDERATION_LIVE=1`.
///
/// ```sh
/// FEDERATION_LIVE=1 swift test --filter RFFMCanaryTests
/// ```
///
/// El filtro es el **nombre del tipo**. `--filter FederationCanary` —el rótulo de
/// este `@Suite`— no casa con nada y devuelve `0 tests … passed`, que se lee como
/// verde: `--filter` es una expresión regular sobre identificadores de Swift.
///
/// # Qué pregunta, y por qué no es lo mismo que el volcado
///
/// | | Responde a | Determinista | Cuándo corre |
/// |---|---|---|---|
/// | Volcado guardado (F2) | *¿he roto yo el parser?* | sí | siempre, sin red |
/// | **Canario** (F5) | *¿han cambiado ellos?* | **no, por naturaleza** | a demanda |
///
/// Fusionarlos las estropea las dos: con una petición de red dentro de la
/// batería, un rojo puede significar que la federación está caída, y entonces el
/// verde deja de significar *"mi cambio está bien"*.
///
/// # **No compara bytes**
///
/// El calendario cambia todas las semanas por diseño —los horarios se fijan el
/// domingo y los marcadores entran el fin de semana ([Anexo RFFM §F.5])—, así
/// que un `diff` contra el fichero guardado daría alarma **cada lunes**, y una
/// bandera que grita siempre es peor que ninguna.
///
/// Lo que se afirma es **estructural**: que el parser sigue tragando, más unos
/// pocos invariantes baratos. Si desaparece el `__NEXT_DATA__`, si `codjornada`
/// deja de ser un número, si cambian los nombres de las claves del partido o se
/// va `calendar.host`, el parser revienta — y ése **es** el aviso.
///
/// # Distingue **tres** cosas, no dos
///
/// Plan §4.4 pedía separar *"cambió la fuente"* de *"caducó la coordenada"*.
/// Escribiéndolo aparecieron tres, y la tercera es la que rompe el supuesto
/// original:
///
/// 1. **`transportFailure`** → no hay red, o la federación está caída. No es un
///    hallazgo: es ruido, y se dice como tal.
/// 2. **`coordinateNotFound`** → revisa la coordenada, no el código.
/// 3. **`malformedResponse`** → **esto es el aviso**: han cambiado ellos.
///
/// Y una cuarta que el diseño no había previsto (`D-84`): la respuesta llega,
/// parsea perfectamente, y **es de otra competición**. La RFFM ignora el
/// parámetro `temporada`, así que basta un dígito mal en `competicion` o `grupo`
/// —los códigos son densos— para caer en otra competición real. Y los códigos de
/// competición y grupo **cambian cada temporada, pero los viejos siguen sirviendo
/// su calendario** —no caducan: sirven lo suyo para siempre—, así que una
/// coordenada equivocada **no da 404**. Se descubrió capturando los dos volcados
/// de esta fase. Por eso el canario compara también el nombre.
@Suite("FederationCanary · Plan §4.4 · el parser contra la respuesta viva",
       .enabled(if: ProcessInfo.processInfo.environment["FEDERATION_LIVE"] == "1",
                "canario: exige FEDERATION_LIVE=1 y conexión a internet"))
struct RFFMCanaryTests {

    /// La coordenada del canario.
    ///
    /// **Caduca, y por eso es configurable.** `temporada` cambia cada año y
    /// `competicion`/`grupo` con ella ([Anexo RFFM §F.1]), así que cablearla
    /// garantiza falsos positivos en cuanto pase la temporada. El valor por
    /// defecto es el del volcado de temporada jugada, para que el canario y el
    /// *fixture* hablen de lo mismo. **Solo `FEDERATION_LIVE=1` es obligatoria**;
    /// las de abajo tienen valor por defecto, y `FEDERATION_LIVE_ROUND` también
    /// (la jornada de la clasificación, ver `round()`).
    ///
    /// ```sh
    /// FEDERATION_LIVE=1 \
    ///   FEDERATION_LIVE_SEASON=22 \
    ///   FEDERATION_LIVE_COMPETITION=… FEDERATION_LIVE_GROUP=… \
    ///   FEDERATION_LIVE_MODALITY=futbol_7 \
    ///   FEDERATION_LIVE_NAME="PREFERENTE AFICIONADO" \
    ///   swift test --filter RFFMCanaryTests
    /// ```
    ///
    /// - Important: el filtro es **`RFFMCanaryTests`, el nombre del tipo**.
    ///   `--filter FederationCanary` —el rótulo del *suite*— no casa con nada y
    ///   devuelve `0 tests … passed`, **que se lee como verde**.
    static func env(_ key: String, _ fallback: String) -> String {
        ProcessInfo.processInfo.environment[key] ?? fallback
    }

    static func coordinate() throws -> FederationCoordinate {
        // La modalidad **también es coordenada**: viaja como `tipojuego` en la
        // URL ([Anexo RFFM §F.1]) y de ella depende qué calendario devuelve la
        // fuente.
        //
        // Estuvo cableada a `.futbol11` hasta que alguien preguntó por qué no
        // estaba entre las variables, y el hueco no era cosmético: `RFFMGameType`
        // documenta que **`3` es fútbol sala y `4` es fútbol-5**, no por orden, y
        // con la modalidad fija esa traducción no la ejercitaba nadie contra la
        // fuente viva. Un club de base juega alevín y benjamín en fútbol-7.
        let raw = env("FEDERATION_LIVE_MODALITY", Modality.futbol11.rawValue)
        let modality = try #require(
            Modality(rawValue: raw),
            """
            FEDERATION_LIVE_MODALITY='\(raw)' no está en el catálogo de §3.3. \
            Valores: \(Modality.allCases.map(\.rawValue).joined(separator: ", ")).
            """)

        return FederationCoordinate(
            federationSeasonID: env("FEDERATION_LIVE_SEASON", "21"),
            federationCompetitionID: env("FEDERATION_LIVE_COMPETITION", "24037548"),
            federationGroupID: env("FEDERATION_LIVE_GROUP", "24037549"),
            modality: modality)
    }

    /// Qué competición se espera encontrar ahí (`D-84`).
    static var expectedName: String {
        env("FEDERATION_LIVE_NAME", "PRIMERA DIVISION AUTONOMICA CADETE")
    }

    /// La jornada de la clasificación (F7). Por defecto la **30**, la del volcado
    /// `RFFM-standings-temp21-group-24037549-round30-29.txt`, para que el canario
    /// y el *fixture* hablen de la misma foto.
    static func round() throws -> Int {
        let raw = env("FEDERATION_LIVE_ROUND", "30")
        return try #require(Int(raw), "FEDERATION_LIVE_ROUND='\(raw)' no es un número de jornada")
    }

    static func client() -> RFFMFederationClient {
        RFFMFederationClient(transport: HTTPFederationTransport())
    }

    /// Lee de la RFFM viva, o dice **por qué no** separando el ruido del aviso.
    ///
    /// Es la misma clasificación para las tres lecturas —calendario,
    /// clasificación y goleadores—, porque las tres pasan por el mismo
    /// transporte y lanzan el mismo `FederationError`. Devuelve `nil` cuando ya
    /// ha dejado escrito el motivo, y el test termina ahí.
    static func live<T>(
        _ reading: String, _ fetch: () async throws -> T
    ) async throws -> T? {
        do {
            return try await fetch()
        } catch let error as FederationError {
            switch error {
            case .transportFailure(_, let reason):
                // Ruido, no hallazgo. Se dice con todas las letras para que nadie
                // abra el parser buscando un fallo que no está ahí.
                Issue.record("""
                    No se pudo hablar con la RFFM (\(reading)). **Esto no es un aviso \
                    del canario**: no hay red, o su servidor está caído. \
                    Motivo: \(reason)
                    """)
                return nil
            case .coordinateNotFound(let detail):
                // **No dice "404" a propósito**: medido contra la RFFM, nunca lo
                // es (`FederationError.coordinateNotFound`). El detalle es texto
                // porque quien lo levanta no siempre sabe a qué URL fue.
                //
                // Y **nombra las tres variables, incluida `_SEASON`**, aunque hoy
                // la fuente ignore `temporada` (`D-84`): eso es una observación
                // sobre un sistema ajeno, no un contrato. Si la RFFM lo hace
                // cumplir, la receta que omitiera la temporada mandaría a buscar
                // por el sitio equivocado — y esto se lee justo el día en que algo
                // cambió de su lado.
                Issue.record("""
                    La coordenada no designa nada (\(reading)): \(detail). Esos \
                    `competicion`/`grupo` no existen — **no es que hayan caducado**: \
                    cada temporada recibe un bloque nuevo y los viejos siguen \
                    sirviendo su calendario ([Anexo RFFM §F.1], `D-84`). **Tampoco es \
                    un cambio de la fuente**: pásale otra con \
                    FEDERATION_LIVE_SEASON / _COMPETITION / _GROUP (y _ROUND para \
                    la clasificación). **Antes, repítelo**: la RFFM sirve `null` \
                    pasajero en clasificación y goleadores para grupos que existen \
                    (H-61), y desde aquí no se distingue de una coordenada que no existe.
                    """)
                return nil
            case .unexpectedStatus(let status, let url):
                Issue.record("""
                    La RFFM respondió \(status) en \(url) (\(reading)). Fallo suyo, \
                    no del parser. Si se repite durante días, mirar si han movido la ruta.
                    """)
                return nil
            case .malformedResponse(let field, let reason):
                // **Éste sí es el aviso.** Es para lo que existe el canario.
                Issue.record("""
                    ⚠️ EL PARSER YA NO TRAGA (\(reading)): \(field) — \(reason).
                    La RFFM ha cambiado la forma de su respuesta. Antes de tocar \
                    código: recapturar el volcado, revalidar el Anexo RFFM y solo \
                    entonces ajustar el parser. Es la lección de D-74.
                    """)
                return nil
            }
        }
    }

    @Test("el parser sigue tragando la respuesta viva de la RFFM (Plan §4.4)")
    func theParserStillSwallowsTheLiveResponse() async throws {
        let coordinate = try Self.coordinate()
        guard let calendar = try await Self.live("calendario", {
            try await Self.client().fetchCalendar(coordinate)
        }) else { return }

        // ── Invariantes baratos, todos estructurales ────────────────────────
        //
        // Ninguno mira un valor concreto: el calendario cambia cada semana por
        // diseño, así que afirmar "la jornada 3 se juega el 12" sería la alarma
        // de cada lunes que Plan §4.4 descarta.

        #expect(!calendar.rounds.isEmpty, "un grupo sin ninguna jornada no es un grupo")
        #expect(calendar.rounds.allSatisfy { $0.number >= 1 },
                "codjornada dejó de ser un número de jornada")
        #expect(calendar.rounds.contains { !$0.matches.isEmpty },
                "ninguna jornada trae partidos: la clave de la lista ha cambiado")

        // El `codacta` es el paso 1 de la cadena de §3.7 y `UNIQUE` en §3.5. Si
        // dejara de ser único, la ingesta emparejaría partidos distintos entre sí.
        let actas = calendar.rounds.flatMap { $0.matches.compactMap(\.federationMatchID) }
        #expect(Set(actas).count == actas.count, "los codacta han dejado de ser únicos")

        // **El sobre la trae opcional desde F6-bis** (H-08: la FCF no la
        // publica), pero **la RFFM sí**, así que aquí un `nil` es señal de las
        // que este canario existe para dar: o cambiaron el formato de
        // `calendar.temporada` o dejaron de mandarlo. `SeasonLabel` ya validó la
        // forma al construirse (`D-71`); llegar con valor significa que la
        // etiqueta sigue siendo derivable.
        #expect(calendar.seasonLabel != nil,
                "la RFFM dejó de publicar una `temporada` con formato AAAA-BBBB")

        // `D-84`: parsea, pero ¿es la competición que creemos? La coordenada
        // equivocada **no da 404**.
        #expect(calendar.competitionName == Self.expectedName, """
            La coordenada devuelve '\(calendar.competitionName ?? "sin nombre")' y se \
            esperaba '\(Self.expectedName)'. La RFFM ignora el parámetro `temporada` (D-84): esto no es un cambio de formato, es que la \
            coordenada apunta a otra cosa.
            """)
    }

    // ── Las otras dos lecturas (`A-15`·H-86) ────────────────────────────────
    //
    // Hasta aquí el canario solo vigilaba el calendario, y `launchd` hace **tres**
    // lecturas cada semana. Los volcados de F7 y F8 contestan *"¿he roto yo el
    // parser?"*; esto contesta *"¿han cambiado ellos?"* para las otras dos.

    @Test("el parser de la clasificación sigue tragando la respuesta viva (F7, A-15·H-86)")
    func theStandingsParserStillSwallowsTheLiveResponse() async throws {
        let coordinate = try Self.coordinate()
        let round = try Self.round()
        guard let standing = try await Self.live("clasificación, jornada \(round)", {
            try await Self.client().fetchStandings(coordinate, round: round)
        }) else { return }

        #expect(!standing.rows.isEmpty, "una clasificación sin filas no es una clasificación")

        // `position` es `minimum: 1` en el *spec* y la tabla es un **bloque**: en
        // el orden publicado, 1, 2, 3… sin huecos. Un hueco o un salto es que la
        // clave de la posición o el orden de la lista han cambiado.
        #expect(standing.rows.map(\.position) == Array(1...max(standing.rows.count, 1)),
                "las posiciones no van de 1 a N en el orden publicado")

        // `puntos_sancion` puede romper `3·G + E` (por eso los puntos no se
        // recalculan), pero **nada** rompe esto: si deja de cumplirse, los
        // contadores han cambiado de clave o de significado.
        let unbalanced = standing.rows.filter { $0.won + $0.drawn + $0.lost != $0.played }
        #expect(unbalanced.isEmpty, """
            ganados + empatados + perdidos ≠ jugados en \(unbalanced.map(\.position)): \
            los contadores han cambiado de clave
            """)

        // `codequipo` es el mismo id que el `codigo_equipo_*` del calendario y es
        // por donde se empareja la fila (§3.7). Repetido, dos filas caerían en el
        // mismo `Team`.
        let teams = standing.rows.compactMap(\.team.federationTeamID)
        #expect(Set(teams).count == teams.count, "un `codequipo` sale en dos filas")

        // **La evidencia más fuerte del puerto** (§F.18): a `/api/standings` no
        // se le envía la competición, así que el código que vuelve **no puede ser
        // eco**. Si no casa, la coordenada apunta a otra liga (`D-84`).
        #expect(standing.federationCompetitionID == coordinate.federationCompetitionID, """
            La clasificación dice ser de la competición \
            '\(standing.federationCompetitionID ?? "sin código")' y se pidió \
            '\(coordinate.federationCompetitionID)': el grupo es de otra competición.
            """)
        #expect(standing.competitionName == Self.expectedName, """
            La clasificación devuelve '\(standing.competitionName ?? "sin nombre")' y se \
            esperaba '\(Self.expectedName)'.
            """)
    }

    @Test("el parser de los goleadores sigue tragando la respuesta viva (F8, A-15·H-86)")
    func theScorersParserStillSwallowsTheLiveResponse() async throws {
        let coordinate = try Self.coordinate()
        guard let table = try await Self.live("goleadores", {
            try await Self.client().fetchScorers(coordinate)
        }) else { return }

        #expect(!table.rows.isEmpty, "un ranking sin filas no es un ranking")

        // El orden publicado es **lo único que hace de ranking**: ninguna fuente
        // publica puesto (§F.19). Si los goles suben al bajar por la lista, la
        // fuente ha dejado de ordenar o la clave de los goles ha cambiado.
        let goals = table.rows.compactMap(\.goals)
        #expect(!goals.isEmpty, "la RFFM publica los goles de cada fila; no ha llegado ninguno")
        #expect(zip(goals, goals.dropFirst()).allSatisfy { $0 >= $1 },
                "los goles no bajan al bajar por el ranking: la fuente ya no ordena")

        // `codigo_jugador` es la clave de *upsert* de `LeagueScorer` (F8). Repetido,
        // dos filas se pisarían en la misma.
        let players = table.rows.compactMap(\.federationPlayerID)
        #expect(Set(players).count == players.count, "un `codigo_jugador` sale en dos filas")

        // Esta ruta **valida que `idGroup` e `idCompetition` sean pareja**
        // (§F.19), así que una coordenada equivocada da `null` y no otra liga.
        // El nombre se mira igual: es la guarda que la pasada aplica (`D-84`).
        #expect(table.competitionName == Self.expectedName, """
            Los goleadores devuelven '\(table.competitionName ?? "sin nombre")' y se \
            esperaba '\(Self.expectedName)'.
            """)
    }
}
