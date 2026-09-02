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
/// parsea perfectamente, y **es de otra competición**. La RFFM reutiliza los
/// códigos de competición y grupo entre temporadas, así que una coordenada
/// caducada **no da 404** — se descubrió capturando los dos volcados de esta
/// fase. Por eso el canario compara también el nombre.
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
    /// las cuatro de abajo tienen valor por defecto.
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

    @Test("el parser sigue tragando la respuesta viva de la RFFM (Plan §4.4)")
    func theParserStillSwallowsTheLiveResponse() async throws {
        let client = RFFMFederationClient(transport: HTTPFederationTransport())

        let calendar: FederationCalendar
        do {
            calendar = try await client.fetchCalendar(try Self.coordinate())
        } catch let error as FederationError {
            switch error {
            case .transportFailure(_, let reason):
                // Ruido, no hallazgo. Se dice con todas las letras para que nadie
                // abra el parser buscando un fallo que no está ahí.
                Issue.record("""
                    No se pudo hablar con la RFFM. **Esto no es un aviso del \
                    canario**: no hay red, o su servidor está caído. \
                    Motivo: \(reason)
                    """)
                return
            case .coordinateNotFound(let url):
                Issue.record("""
                    404 en \(url). La coordenada ha caducado — `temporada` cambia \
                    cada año ([Anexo RFFM §F.1]). **No es un cambio de la fuente**: \
                    pásale otra con FEDERATION_LIVE_SEASON / _COMPETITION / _GROUP.
                    """)
                return
            case .unexpectedStatus(let status, let url):
                Issue.record("""
                    La RFFM respondió \(status) en \(url). Fallo suyo, no del \
                    parser. Si se repite durante días, mirar si han movido la ruta.
                    """)
                return
            case .malformedResponse(let field, let reason):
                // **Éste sí es el aviso.** Es para lo que existe el canario.
                Issue.record("""
                    ⚠️ EL PARSER YA NO TRAGA: \(field) — \(reason).
                    La RFFM ha cambiado la forma de su respuesta. Antes de tocar \
                    código: recapturar el volcado, revalidar el Anexo RFFM y solo \
                    entonces ajustar el parser. Es la lección de D-74.
                    """)
                return
            }
        }

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

        // `SeasonLabel` ya validó la forma al construirse (`D-71`); llegar aquí
        // significa que la etiqueta sigue teniendo el formato del que se deriva.
        #expect(!calendar.seasonLabel.value.isEmpty)

        // `D-84`: parsea, pero ¿es la competición que creemos? La coordenada
        // caducada **no da 404**.
        #expect(calendar.competitionName == Self.expectedName, """
            La coordenada devuelve '\(calendar.competitionName ?? "sin nombre")' y se \
            esperaba '\(Self.expectedName)'. La RFFM reutiliza los códigos entre \
            temporadas (D-84): esto no es un cambio de formato, es que la \
            coordenada apunta a otra cosa.
            """)
    }
}
