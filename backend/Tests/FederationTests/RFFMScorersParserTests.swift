import Application
import Foundation
import Testing

@testable import Federation

/// Nivel 1 (§8.1): **el parser de goleadores de la RFFM**, contra el volcado
/// real. Sin red y sin Docker.
///
/// El volcado es `RFFM-scorers-group-24037549.txt` —PRIMERA DIVISION AUTONOMICA
/// CADETE Grupo 1, 2025-26, **218 filas**—, que es **el mismo grupo** que el del
/// calendario y el de la clasificación, descrito en [Anexo RFFM §F.19]. Y
/// `RFFM-scorers-coordenada-inexistente.txt` trae las **tres** formas de no
/// designar nada, las tres con el mismo cuerpo: `null`.
///
/// # Lo que esta suite vigila, y son dos cosas distintas
///
/// 1. **Que el "no" se detecte igual que en la clasificación y no como en el
///    calendario.** El documento entero es `null`, así que se decodifica a
///    **opcional**; escrito por analogía con el calendario —mirar un campo— eso
///    sería un `DecodingError` → `malformedResponse` → el canario gritando *"¡han
///    cambiado la forma!"* cada vez que alguien se equivoque de número (`D-84`).
/// 2. **Que una fila rara no tire el ranking entero**, que es donde este parser
///    **sí** se separa del de la clasificación. Allí los ocho contadores son
///    obligatorios porque una tabla con un hueco en la numeración no es una
///    tabla; aquí las filas son independientes, así que lo que no se entiende
///    llega como `nil` y lo descarta el caso de uso.
@Suite("RFFMScorersParser · §F.19 · los goleadores contra el volcado real")
struct RFFMScorersParserTests {

    static func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil),
            "no encuentro el volcado \(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// El volcado no es el cuerpo: lleva la URL arriba y el código HTTP abajo,
    /// para que dentro de tres años no haya que volver a preguntárselo a la
    /// fuente. El parser recibe **solo el cuerpo**, que es lo que le da el
    /// transporte. Mismo criterio y mismo formato que el de la clasificación.
    static func bodies(ofDump raw: String) -> [String] {
        raw.components(separatedBy: "https://www.rffm.es/api/")
            .dropFirst()
            .map { block in
                block
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .dropFirst()                                   // la cola de la URL
                    .filter { !$0.hasPrefix("HTTP ") }             // el código, abajo
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    static func scorersBody() throws -> String {
        try #require(bodies(ofDump: try fixture("RFFM-scorers-group-24037549.txt")).first)
    }

    /// Los **tres** cuerpos de coordenada mala: par inexistente, grupo bueno con
    /// competición mala, y grupo bueno sin competición.
    static func missingCoordinateBodies() throws -> [String] {
        bodies(ofDump: try fixture("RFFM-scorers-coordenada-inexistente.txt"))
    }

    // ── El sobre: un campo, y el resto se queda fuera a propósito ────────────

    @Test("el nombre de la competición llega, y es lo único del sobre que se lee (§F.19)")
    func theCompetitionNameComesBack() throws {
        let table = try RFFMScorersParser.parse(try Self.scorersBody())

        // Es el único campo del sobre con lector: la guarda de `D-84`
        // (`Competition.requireSameSource`). No es eco —lo que se manda son
        // números y lo que vuelve es texto— pero sí es **ciego a la temporada**,
        // porque §F.17 midió que el nombre es idéntico entre temporadas.
        #expect(table.competitionName == "PRIMERA DIVISION AUTONOMICA CADETE")
    }

    @Test("y el DTO NO trae identificador de competición, porque aquí sólo podría ser eco (§F.19)")
    func theEnvelopeCarriesNoCompetitionCode() throws {
        // Comprobación de **forma**, no de valor: `FederationStanding` sí tiene
        // ese campo y §F.18 lo celebró como la evidencia más fuerte del puerto,
        // porque a `/api/standings` no se le envía. A esta ruta **sí** se le envía
        // `idCompetition`, así que un campo así sería la trampa de §F.16. Que este
        // test sea una línea que no compila si alguien lo añade es justamente el
        // punto: el tipo es la afirmación.
        let table = try RFFMScorersParser.parse(try Self.scorersBody())
        #expect(Mirror(reflecting: table).children.count == 2)
    }

    // ── Las filas ────────────────────────────────────────────────────────────

    @Test("las 218 filas del volcado entran enteras (§F.19)")
    func allRowsAreParsed() throws {
        let table = try RFFMScorersParser.parse(try Self.scorersBody())
        #expect(table.rows.count == 218)
    }

    @Test("la primera fila, campo a campo (§F.19)")
    func theFirstRowFieldByField() throws {
        let table = try RFFMScorersParser.parse(try Self.scorersBody())
        let first = try #require(table.rows.first)

        #expect(first.federationPlayerID == "11322891")
        #expect(first.fullName == "GEA IRISARRI, LUIS")
        #expect(first.goals == 31)

        // **La letra va pegada al nombre y NO se parte**, al revés que en el
        // calendario, donde la RFFM la escribe entre comillas simples
        // ([Anexo RFFM §F.5]). Aquí el texto solo se pinta (`D-32`), así que
        // partirlo sería trabajo con riesgo y sin lector.
        #expect(first.teamLabel == "ARAVACA C.F. - CEIBA A")
    }

    @Test("el puesto llega nulo, porque esta fuente no lo publica (§F.13, §F.19)")
    func rankIsAlwaysNil() throws {
        let table = try RFFMScorersParser.parse(try Self.scorersBody())

        // Las 218, no solo la primera: lo que se afirma es que **no existe el
        // campo**, no que la fila de arriba no lo traiga.
        #expect(table.rows.allSatisfy { $0.rank == nil })
    }

    @Test("y el parser NO numera las filas por su orden (spec `rank`, §F.19)")
    func theParserDoesNotSynthesizeRank() throws {
        let table = try RFFMScorersParser.parse(try Self.scorersBody())

        // Es la tentación entera de este endpoint: la lista viene ordenada por
        // goles descendente, así que `rank = índice + 1` parece gratis. **No lo
        // es.** El *spec* se comprometió a respetar el puesto del proveedor
        // *"porque los criterios de desempate son suyos y no los conocemos"*, y
        // hay empates de verdad en el volcado — numerarlos sería inventarse ese
        // desempate y servirlo con cara de dato de la fuente.
        #expect(table.rows.first?.rank == nil)
        #expect(table.rows.last?.rank == nil)
    }

    @Test("los identificadores de jugador llegan todos, y son 218 distintos (D-93)")
    func everyRowCarriesItsPlayerID() throws {
        let table = try RFFMScorersParser.parse(try Self.scorersBody())
        let ids = table.rows.compactMap(\.federationPlayerID)

        // Es la medición sobre la que se apoya `D-93`: la clave de *upsert*
        // existe en el 100% de las filas y no se repite. Sin esto, la decisión
        // sería una apuesta.
        #expect(ids.count == 218)
        #expect(Set(ids).count == 218)
        #expect(ids.allSatisfy { !$0.isEmpty })
    }

    @Test("la lista viene ordenada por goles descendente, y se respeta (§F.19)")
    func theOrderIsPreserved() throws {
        let table = try RFFMScorersParser.parse(try Self.scorersBody())
        let goals = table.rows.compactMap(\.goals)

        #expect(goals == goals.sorted(by: >))
        #expect(goals.first == 31)
        #expect(goals.last == 1)
    }

    // ── La coordenada que no designa nada (§F.19, D-84) ──────────────────────

    @Test("las tres formas de coordenada mala dan `coordinateNotFound`, no `malformedResponse` (§F.19)")
    func aBadCoordinateIsNotAFormatChange() throws {
        let bodies = try Self.missingCoordinateBodies()

        // **Tres y no una**, que es lo que esta ruta añade sobre su vecina: el par
        // inexistente, el grupo bueno con competición mala, y el grupo bueno sin
        // competición. Las tres responden `200` + `null`.
        #expect(bodies.count == 3)

        for body in bodies {
            #expect(throws: FederationError.self) { try RFFMScorersParser.parse(body) }
            do {
                _ = try RFFMScorersParser.parse(body)
                Issue.record("debería haber lanzado: el cuerpo es `null`")
            } catch let error as FederationError {
                guard case .coordinateNotFound = error else {
                    // Si esto salta como `malformedResponse`, el canario dará la
                    // alarma de "han cambiado la forma" cada vez que alguien se
                    // equivoque de número. Es el punto 2 de `D-84`.
                    Issue.record("esperaba coordinateNotFound y llegó \(error)")
                    return
                }
            }
        }
    }

    @Test("un cuerpo que no es de esta ruta SÍ es `malformedResponse` (D-84, punto 2)")
    func aChangedShapeIsNotABadCoordinate() {
        // La otra mitad del par. Sin este test, un parser que devolviera
        // `coordinateNotFound` para todo pasaría el de arriba — y el canario se
        // quedaría mudo justo cuando la fuente cambie de forma, que es para lo
        // único que existe.
        #expect(throws: FederationError.self) {
            try RFFMScorersParser.parse(#"{"estado":"1","goles":"esto no es un array"}"#)
        }
        do {
            _ = try RFFMScorersParser.parse(#"{"estado":"1","goles":"no es un array"}"#)
            Issue.record("debería haber lanzado")
        } catch let error as FederationError {
            guard case .malformedResponse = error else {
                Issue.record("esperaba malformedResponse y llegó \(error)")
                return
            }
        } catch {
            Issue.record("error inesperado: \(error)")
        }
    }

    // ── Lo que no se entiende se degrada, no revienta ────────────────────────

    @Test("una fila sin identificador no tira el ranking: llega con `nil` (D-86 a escala de fila)")
    func anUnidentifiedRowDoesNotKillTheTable() throws {
        let body = """
            {"estado":"1","competicion":"X","grupo":"Grupo 1","goles":[
              {"codigo_jugador":"","jugador":"SIN CODIGO","nombre_equipo":"EQ A","goles":"9"},
              {"codigo_jugador":"77","jugador":"CON CODIGO","nombre_equipo":"EQ B","goles":"8"}]}
            """
        let table = try RFFMScorersParser.parse(body)

        // **Las dos llegan.** Quién se queda fuera lo decide el caso de uso, que
        // es quien sabe que la clave es obligatoria (`D-93`) y quien tiene dónde
        // apuntar el descarte. Un parser que filtrara aquí escondería la fila sin
        // dejar rastro.
        #expect(table.rows.count == 2)
        // **Acceso sin subíndice a propósito**: contra el esqueleto la lista está
        // vacía, y un `rows[0]` ahí no da un rojo de aserción — da un
        // `Index out of range` que se lleva la ejecución entera, que es el mismo
        // efecto que el `fatalError()` que Plan §5.1 prohíbe en los esqueletos.
        #expect(table.rows.first?.federationPlayerID == nil)
        #expect(table.rows.dropFirst().first?.federationPlayerID == "77")
    }

    @Test("y unos goles que no son número llegan como `nil`, no como cero (D-56)")
    func unreadableGoalsAreNilAndNotZero() throws {
        let body = """
            {"estado":"1","goles":[
              {"codigo_jugador":"77","jugador":"A","nombre_equipo":"EQ","goles":""},
              {"codigo_jugador":"78","jugador":"B","nombre_equipo":"EQ","goles":"—"}]}
            """
        let table = try RFFMScorersParser.parse(body)

        // La distinción entera de `D-56`: **ausente o vacío no es un valor**. Un
        // `0` aquí diría "este jugador no ha marcado", que es un dato, y el que
        // hay es "la fuente no lo dijo".
        #expect(table.rows.allSatisfy { $0.goals == nil })
    }

    @Test("el sobre puede faltar entero y las filas siguen entrando (H-08, la FCF no manda sobre)")
    func theEnvelopeIsOptional() throws {
        let body = #"{"goles":[{"codigo_jugador":"1","jugador":"A","nombre_equipo":"E","goles":"3"}]}"#
        let table = try RFFMScorersParser.parse(body)

        // Es la lección de `A-1`/H-08 hecha test: el sobre de la RFFM no puede ser
        // obligatorio, porque el equivalente catalán es **un array pelado**
        // ([Anexo FCF §C.10.7]). Aquí se ejercita contra la propia RFFM para que
        // el día que exista el adaptador de la FCF el puerto ya aguante.
        #expect(table.competitionName == nil)
        #expect(table.rows.count == 1)
    }
}
