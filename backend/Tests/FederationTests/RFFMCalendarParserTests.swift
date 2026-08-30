import Foundation
import Testing
import Application
import Domain
@testable import Federation

/// Nivel 1 (§8.1): **cero I/O de red**. Lee un *fixture* de disco, que es el
/// volcado real guardado en `docs/Federation APIs examples/`.
///
/// Plan §4.1: *"F2 · adaptador RFFM del calendario, contra fixtures. **Sin
/// persistir nada**"*. Esta suite es el grueso de esa fase.
@Suite("RFFM · parser del calendario · Anexo RFFM §F.15")
struct RFFMCalendarParserTests {

    /// El volcado del 2026-08-28:
    /// `temporada=22&tipojuego=1&competicion=26737701&grupo=26737702`.
    /// PREFERENTE AFICIONADO, Grupo 1 — **34 jornadas, 18 equipos, 306 partidos.**
    ///
    /// **`.html` y no `.txt` porque es HTML**: la RFFM sirve el calendario como
    /// página, con el JSON dentro de un `__NEXT_DATA__` ([Anexo RFFM §F.7]). Y
    /// **`sin-jugar` va en el nombre porque es la limitación de esta muestra**: la
    /// temporada no ha arrancado, así que los 306 partidos llegan sin marcador y
    /// sin hora. La rama de "partido jugado" no la ejercita nadie hasta F5.
    static let fixture: String = {
        let url = Bundle.module.url(
            forResource: "RFFM-calendario-temporada-sin-jugar", withExtension: "html",
            subdirectory: "Fixtures"
        )!
        return try! String(contentsOf: url, encoding: .utf8)
    }()

    private func parse() throws -> FederationCalendar {
        try RFFMCalendarParser.parse(Self.fixture)
    }

    // ── El sobre ─────────────────────────────────────────────────────────────

    /// §F.7 y §F.15: el calendario es **HTML**, y el JSON viene dentro de un
    /// `<script id="__NEXT_DATA__">`. Va **seguido del cierre `</script>`**, así
    /// que el *decoder* tiene que parar donde acaba el objeto.
    @Test("extrae el JSON del __NEXT_DATA__ y no se atraganta con el </script> (§F.7, §F.15)")
    func extractsEmbeddedJSON() throws {
        let calendar = try parse()
        #expect(calendar.rounds.count == 34)
    }

    @Test("lee los 306 partidos de las 34 jornadas (§F.15)")
    func readsEveryMatch() throws {
        let calendar = try parse()
        #expect(calendar.rounds.allSatisfy { $0.matches.count == 9 })
        #expect(calendar.rounds.reduce(0) { $0 + $1.matches.count } == 306)
    }

    /// **El test que paga la corrección de §F.11.** La app heredada asignaba la
    /// jornada por índice de array; el anexo decía "usar `jornada`" y **estaba
    /// mal**: `jornada` es el rótulo `"1 (13-09-2026)"`. El número está en
    /// `codjornada`.
    ///
    /// Si alguien "arregla" esto leyendo `jornada`, `Int("1 (13-09-2026)")` da
    /// `nil` — y el fallo se vería aquí, no en producción.
    @Test("el número de jornada sale de codjornada, no del rótulo `jornada` (§F.15)")
    func roundNumberComesFromCodjornada() throws {
        let calendar = try parse()
        #expect(calendar.rounds.map(\.number) == Array(1...34))
        #expect(calendar.rounds[0].label == "1 (13-09-2026)")
        #expect(calendar.rounds[33].label == "34 (06-06-2027)")
    }

    /// §F.7: `currentRound` viene en el calendario y la app **no lo usa**. Es el
    /// mejor disparador para una ingesta incremental, así que el puerto lo expone.
    @Test("expone currentRound, que la app heredada ignoraba (§F.7)")
    func exposesCurrentRound() throws {
        #expect(try parse().currentRound == 1)
    }

    /// §F.15: los tres rótulos del alta llegan en el propio calendario, así que
    /// la cascada de `D-67` no necesita una segunda llamada para tenerlos.
    /// `competitionName` es el `federation_name` de `D-72` — **evidencia, no
    /// rótulo**.
    @Test("trae los rótulos del alta: nombre de competición, grupo y temporada (§F.15, D-72)")
    func exposesLabels() throws {
        let calendar = try parse()
        #expect(calendar.competitionName == "PREFERENTE AFICIONADO")
        #expect(calendar.groupLabel == "Grupo 1")
        #expect(calendar.seasonLabel.value == "2026/27")
    }

    // ── El partido ───────────────────────────────────────────────────────────

    /// Volcado literal del primer partido, campo a campo. Si la fuente cambia la
    /// forma, este test es el que lo dice.
    @Test("mapea el primer partido campo a campo (§F.2, §F.15)")
    func mapsFirstMatch() throws {
        let match = try #require(try parse().rounds.first?.matches.first)

        #expect(match.federationMatchID == "5589120")
        #expect(match.home.federationTeamID == "439")
        #expect(match.home.name == "C.D. GALAPAGAR")
        #expect(match.home.letter == "B")
        #expect(match.home.federationClubID == "0011078749")
        #expect(match.away.federationTeamID == "10656492")
        #expect(match.away.name == "S.A.D. FOMENTO ALUMNI")
        #expect(match.away.letter == "A")
        #expect(match.away.federationClubID == "0011595212")
        #expect(match.venue == "GALAPAGAR - EL CHOPO")
        #expect(match.venueCode == "1212")
    }

    /// §F.15: el *host* del escudo **viene en el payload** (`calendar.host`), no
    /// es constante nuestra como daba por hecho §F.4.
    @Test("compone la URL del escudo con el host que publica la fuente (§F.15)")
    func buildsCrestURLFromPayloadHost() throws {
        let match = try #require(try parse().rounds.first?.matches.first)
        #expect(match.home.crestURL ==
            "https://appweb.rffm.es/pnfg/pimg/Clubes/00100_0011078749_Escudo_CDG.png")
    }

    /// §F.12: 240 de 240 partidos traían `codacta`, y aquí son **306 de 306, todos
    /// distintos**. La cadena de degradación de `D-31` es una **red de seguridad,
    /// no el camino habitual** — este test es lo que sostiene esa afirmación.
    @Test("los 306 partidos traen codacta y ninguno se repite (§F.12, D-31)")
    func everyMatchHasAUniqueID() throws {
        let ids = try parse().rounds.flatMap(\.matches).map(\.federationMatchID)
        #expect(ids.allSatisfy { $0 != nil })
        #expect(Set(ids.compactMap { $0 }).count == 306)
    }

    /// §F.5 y §F.15: esta muestra es de una temporada **sin arrancar**, así que
    /// todas las fechas son el sábado por defecto y **no hay ni marcador ni hora**.
    /// Es el calendario publicándose en dos tiempos, no datos rotos.
    @Test("una temporada sin arrancar no trae marcador ni hora, y eso es correcto (§F.5)")
    func unplayedSeasonHasNoScoresAndNoKickoffs() throws {
        let matches = try parse().rounds.flatMap(\.matches)
        #expect(matches.allSatisfy { $0.homeScore == nil && $0.awayScore == nil })
        #expect(matches.allSatisfy { $0.kickoff == nil })
        #expect(matches.allSatisfy { $0.date != nil })
        // 34 fechas distintas, una por jornada: el sábado por defecto de §F.5.
        #expect(Set(matches.compactMap(\.date)).count == 34)
    }

    // ── Lo que debe fallar ───────────────────────────────────────────────────

    /// §F.7: la app heredada *"imprime el código HTTP pero no lo valida"*, así que
    /// un 500 acababa en el parser de JSON con un error engañoso. Aquí el error es
    /// explícito y dice dónde mirar.
    @Test("un cuerpo que no es el calendario falla con un error que se entiende (§F.7)", arguments: [
        "", "<html><body>error 500</body></html>",
        #"<script id="__NEXT_DATA__" type="application/json">{"props":{}}</script>"#,
    ])
    func failsLoudlyOnGarbage(_ body: String) {
        #expect(throws: FederationError.self) { try RFFMCalendarParser.parse(body) }
    }

    // ── Coordenada mala ≠ formato cambiado (Plan §4.4, medido en F5) ────────

    /// **El diseño daba por hecho que una coordenada caducada daría 404. No lo
    /// da.** Medido contra la RFFM al escribir el canario de F5: con
    /// `competicion` y `grupo` inexistentes responde **`200`** y una página
    /// completa cuyo `calendar` es **`null`**.
    ///
    /// Sin esta rama, esa respuesta se cae por el `catch` del decodificador y sale
    /// `malformedResponse` — es decir, el canario gritaría *"¡han cambiado la
    /// forma de la respuesta!"* cuando lo que pasa es que la coordenada está mal.
    /// Es exactamente la bandera que grita sin motivo de la que avisa Plan §4.4,
    /// y a las tres semanas nadie la mira.
    ///
    /// El *fixture* es la respuesta real de
    /// `temporada=21&…&competicion=99999999&grupo=99999999`.
    @Test("una coordenada inexistente se llama coordenada, no formato (Plan §4.4)")
    func absentCalendarIsNotAFormatChange() throws {
        let url = Bundle.module.url(
            forResource: "RFFM-calendario-coordenada-inexistente", withExtension: "html",
            subdirectory: "Fixtures")!
        let page = try String(contentsOf: url, encoding: .utf8)

        #expect(throws: FederationError.self) { try RFFMCalendarParser.parse(page) }

        do {
            _ = try RFFMCalendarParser.parse(page)
            Issue.record("se esperaba un error")
        } catch let error as FederationError {
            guard case .coordinateNotFound = error else {
                Issue.record("se esperaba coordinateNotFound y llegó \(error)")
                return
            }
        }
    }

    /// El segundo disfraz de lo mismo, y **peor**: con una `temporada`
    /// inexistente la RFFM devuelve `200` y **el calendario entero de otra
    /// temporada**, con `temporada` vacía. Es decir, ignora el parámetro.
    ///
    /// La única señal es ese campo vacío. Sin esta rama, `SeasonLabel` fallaría al
    /// reformatearlo (`D-71`) y saldría otra vez `malformedResponse` — con 30
    /// jornadas perfectamente parseadas detrás, listas para escribirse en la
    /// temporada equivocada si alguien decidiera "tolerar" el fallo.
    ///
    /// El JSON es mínimo a propósito: lo que se prueba es **una rama**, y el
    /// volcado real de este caso son 392 KB idénticos a otro que ya está.
    @Test("una temporada vacía es coordenada mala, no formato (Plan §4.4)")
    func emptySeasonIsNotAFormatChange() throws {
        let page = #"""
            <script id="__NEXT_DATA__" type="application/json">
            {"props":{"pageProps":{"calendar":{"estado":"1","competicion":\#
            "PRIMERA DIVISION AUTONOMICA CADETE","grupo":"Grupo 1","temporada":"",\#
            "host":"https://appweb.rffm.es/","rounds":[]}}}}
            </script>
            """#

        do {
            _ = try RFFMCalendarParser.parse(page)
            Issue.record("se esperaba un error")
        } catch let error as FederationError {
            guard case .coordinateNotFound = error else {
                Issue.record("se esperaba coordinateNotFound y llegó \(error)")
                return
            }
        }
    }
}
