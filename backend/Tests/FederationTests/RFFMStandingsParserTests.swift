import Application
import Foundation
import Testing

@testable import Federation

/// Nivel 1 (§8.1): **el parser de la clasificación de la RFFM**, contra el
/// volcado real. Sin red y sin Docker.
///
/// El volcado es `RFFM-standings-temp21-group-24037549-round30-29.txt` —PRIMERA
/// DIVISION AUTONOMICA CADETE Grupo 1, 2025-26, jornadas 30 y 29—, descrito campo
/// a campo en [Anexo RFFM §F.18]. Y el segundo,
/// `RFFM-standings-coordenada-inexistente.txt`, son cuatro bytes: `null`.
///
/// # Lo que esta suite vigila y no es obvio
///
/// Que **no se copie la forma del parser del calendario**. Allí *"la coordenada
/// no designa nada"* se detecta mirando un **campo** a nulo dentro de una página
/// entera; aquí **el documento entero es `null`** y no hay campo que mirar. Un
/// parser escrito por analogía convertiría eso en un `DecodingError` →
/// `malformedResponse` → el canario gritando *"¡han cambiado la forma!"* cada vez
/// que alguien se equivoque de número, que es justo la falsa alarma que el punto
/// 2 de `D-84` existe para evitar.
@Suite("RFFMStandingsParser · §F.18 · la clasificación contra el volcado real")
struct RFFMStandingsParserTests {

    static func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil),
            "no encuentro el volcado \(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// **El volcado no es el cuerpo**, y confundirlos es fácil.
    ///
    /// Un volcado guarda la URL arriba y —desde la regla que este proyecto se puso
    /// el 2026-09-15— el **código HTTP** abajo, para que dentro de tres años no
    /// haya que volver a preguntárselo a la fuente. El parser recibe lo que le da
    /// el transporte, que es **solo el cuerpo**. Esto quita el envoltorio, que es
    /// lo que haría `curl` sin `-w`.
    ///
    /// Devuelve una lista porque el volcado de las dos jornadas trae **dos**
    /// respuestas en un fichero, cada una con su URL delante.
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

    static func rounds() throws -> [String] {
        bodies(ofDump: try fixture("RFFM-standings-temp21-group-24037549-round30-29.txt"))
    }

    static func round30() throws -> String { try #require(rounds().first) }
    static func round29() throws -> String { try #require(rounds().last) }

    /// El cuerpo del volcado de coordenada inexistente: `null` a secas.
    static func missingCoordinateBody() throws -> String {
        try #require(
            bodies(ofDump: try fixture("RFFM-standings-coordenada-inexistente.txt")).first)
    }

    // ── El sobre: solo lo que lee alguien ────────────────────────────────────

    @Test("el código de competición llega, y es la evidencia que el calendario no tiene (§F.18)")
    func theCompetitionCodeComesBack() throws {
        let standing = try RFFMStandingsParser.parse(try Self.round30())

        // A `/api/standings` se le mandan `idGroup` y `round` y nada más, así que
        // esto **no puede ser eco**: es la fuente diciendo a qué competición
        // pertenece el grupo que se pidió. Comparado con
        // `Competition.federationCompetitionID` da igualdad de identificadores, no
        // de rótulos — que es más fuerte que la guarda del calendario, obligada a
        // comparar el nombre (`D-91`: idéntico entre temporadas).
        #expect(standing.federationCompetitionID == "24037548")
        #expect(standing.competitionName == "PRIMERA DIVISION AUTONOMICA CADETE")
    }

    // ── Las filas ───────────────────────────────────────────────────────────

    @Test("las 16 filas del grupo, en el orden que las publica la fuente (§F.18)")
    func theSixteenRowsArriveInSourceOrder() throws {
        let standing = try RFFMStandingsParser.parse(try Self.round30())

        #expect(standing.rows.count == 16)
        // No se reordenan aquí: el orden oficial **es un dato**, y `D-92` mide en
        // qué se diferencia del nuestro. Reordenarlo en el parser borraría la
        // única prueba de esa diferencia.
        #expect(standing.rows.map(\.position) == Array(1...16))
    }

    @Test("los ocho contadores de la primera fila, uno a uno (§F.18)")
    func theEightCountersOfTheTopRow() throws {
        let top = try #require(try RFFMStandingsParser.parse(try Self.round30()).rows.first)

        // Transcritos del volcado. El aviso de §F.8 que sigue vivo: **el orden en
        // el JSON es `ganados, perdidos, empatados`**, así que leerlos por
        // posición cruzaría empates con derrotas sin que nada chille — 4 y 3 aquí,
        // dos números pequeños y parecidos.
        #expect(top.position == 1)
        #expect(top.played == 30)
        #expect(top.won == 23)
        #expect(top.drawn == 4)
        #expect(top.lost == 3)
        #expect(top.goalsFor == 78)
        #expect(top.goalsAgainst == 23)
        #expect(top.points == 73)
    }

    @Test("el equipo llega como `FederationTeamRef`, con la letra ya suelta (§3.7)")
    func theTeamArrivesAsATeamRef() throws {
        let top = try #require(try RFFMStandingsParser.parse(try Self.round30()).rows.first)

        // El mismo tipo que el calendario, y a propósito: la fila hay que
        // emparejarla con un `Team` por la cadena de §3.7 igual que un partido.
        // `codequipo` **es** el `codigo_equipo_*` del calendario (§F.8), así que
        // la unión va por id y no degrada a nombre.
        #expect(top.team.federationTeamID == "3350761")
        #expect(top.team.name == "C.D.E. FOOTBALL DREAMS EXPERIENCE")
        #expect(top.team.letter == "A")
        // Del nombre del fichero del escudo sale la clave de club ([Anexo RFFM §F.4]).
        #expect(top.team.federationClubID == "0011221693")
    }

    @Test("la jornada 29 es otra foto, no la misma (§3.2, D-33)")
    func theEarlierRoundIsADifferentSnapshot() throws {
        let thirty = try RFFMStandingsParser.parse(try Self.round30())
        let twentyNine = try RFFMStandingsParser.parse(try Self.round29())

        // Es lo que hace que `StandingRow` sea un *snapshot* y que la columna PREV
        // signifique algo: el par de jornadas consecutivas del mismo grupo tiene
        // que dar dos tablas distintas.
        #expect(twentyNine.rows.count == 16)
        #expect(thirty.rows.map(\.played) != twentyNine.rows.map(\.played))
    }

    // ── Cómo dice la RFFM que no, que aquí NO es como en el calendario ──────

    @Test("un cuerpo `null` es 'la coordenada no designa nada', no 'cambió el formato' (§F.18, D-84)")
    func anullBodyIsACoordinateProblem() throws {
        // Medido el 2026-09-15: `idGroup=99999999` responde **200** y el cuerpo
        // son cuatro bytes, `null`. No hay sobre, ni `estado`, ni lista vacía.
        let body = try Self.missingCoordinateBody()
        #expect(body == "null")

        #expect(throws: FederationError.self) {
            try RFFMStandingsParser.parse(body)
        }
        // Y **con su nombre**: si saliera `malformedResponse`, el canario diría
        // "han cambiado la forma de la respuesta" cada vez que alguien teclee mal
        // un número (`D-84`, punto 2).
        let error = #expect(throws: FederationError.self) {
            try RFFMStandingsParser.parse(body)
        }
        guard case .coordinateNotFound = try #require(error) else {
            Issue.record("esperaba `coordinateNotFound`, llegó \(String(describing: error))")
            return
        }
    }

    @Test("el `null` puede venir con lo que curl le pegue alrededor")
    func thenullSurvivesTheDumpWrapping() throws {
        // El volcado guarda la URL arriba y el `HTTP 200` abajo, que es la regla
        // que este proyecto se puso al recapturar. El parser recibe **el cuerpo**,
        // así que lo que tiene que reconocer es `null` a secas, con o sin espacios.
        for body in ["null", "null\n", "  null  "] {
            #expect(throws: FederationError.self) { try RFFMStandingsParser.parse(body) }
        }
    }

    @Test("un cuerpo que no es JSON sí es 'cambió el formato' (Plan §4.4)")
    func garbageIsAFormatProblem() {
        // La otra mitad del par, y la que impide que la rama de arriba se coma
        // todos los errores: si la fuente devuelve HTML, o un JSON con otra forma,
        // eso **sí** es lo que el canario existe para gritar.
        let error = #expect(throws: FederationError.self) {
            try RFFMStandingsParser.parse("<html>vaya</html>")
        }
        guard case .malformedResponse = try? #require(error) else {
            Issue.record("esperaba `malformedResponse`, llegó \(String(describing: error))")
            return
        }
    }
}
