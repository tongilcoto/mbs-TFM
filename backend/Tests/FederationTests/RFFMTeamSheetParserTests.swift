import Foundation
import Testing
import Application
import Domain
@testable import Federation

/// Nivel 1 (§8.1), **sin red**: la ficha de equipo de la RFFM (`fichaequipo/<código>`), de donde sale la plantilla
/// que se sincroniza ([D-120], R6.14). Contra la grabación de verdad con los datos personales cambiados
/// (`Tools/Fixtures/anonymize-rffm-team-sheet.swift`, decisión 2 de R6.14), y con páginas mínimas para lo que la
/// grabación no enseña.
@Suite("RFFMTeamSheetParser · D-120 · la plantilla de la ficha de equipo")
struct RFFMTeamSheetParserTests {

    static func fixture() throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/RFFM-fichaequipo", withExtension: "html"),
            "no encuentro la grabación de la ficha de equipo")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Una página como la de la RFFM, con solo lo que lee el lector: el bloque de datos y el equipo.
    static func page(team: String) -> String {
        """
        <html><body><div id="__next"></div>
        <script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"team":\(team)}},"page":"/fichaequipo/[...codficha]"}</script>
        </body></html>
        """
    }

    static func names(_ names: [String]) -> String {
        let players = names.map { #"{"cod_jugador":"1","nombre":"\#($0)"}"# }.joined(separator: ",")
        return page(team: #"{"codigo_equipo":"821","jugadores_equipo":[\#(players)]}"#)
    }

    // ── La grabación ──

    @Test("los 24 jugadores de la grabación, en el orden en que los publica")
    func readsTheRecording() throws {
        let roster = try RFFMTeamSheetParser.parse(try Self.fixture())

        #expect(roster.players.count == 24)
        #expect(roster.players.first?.publishedName == "GARCÍA LÓPEZ, JUAN CARLOS")
    }

    /// La RFFM los publica como «APELLIDOS, NOMBRE»; el sistema los guarda como «NOMBRE APELLIDOS» (plan R6,
    /// decisión 9). **Solo se da la vuelta por la coma**: lo demás —que sea un nombre válido— lo mira el dominio.
    @Test("cada nombre, vuelto por la coma: «NOMBRE APELLIDOS», con partículas, guion y un solo apellido")
    func flipsTheNames() throws {
        let roster = try RFFMTeamSheetParser.parse(try Self.fixture())
        let names = roster.players.map(\.fullName)

        #expect(names.contains("JUAN CARLOS GARCÍA LÓPEZ"))
        #expect(names.contains("PABLO DE LA FUENTE MARTÍN"))
        #expect(names.contains("HUGO PÉREZ-REVERTE GIL"))
        #expect(names.contains("DANIEL GÓMEZ"))
        #expect(names.allSatisfy { $0 != nil }, "en la grabación todos llevan una coma, como los 46 medidos")
    }

    // ── Lo que la grabación no enseña ──

    @Test("los espacios de los lados de cada mitad, fuera")
    func trimsBothHalves() throws {
        let roster = try RFFMTeamSheetParser.parse(Self.names(["  GARCÍA LÓPEZ ,  JUAN  "]))

        #expect(roster.players.first?.fullName == "JUAN GARCÍA LÓPEZ")
        #expect(roster.players.first?.publishedName == "  GARCÍA LÓPEZ ,  JUAN  ", "como lo escribe la federación")
    }

    /// Sin coma, con dos, o con una mitad vacía, no se sabe dónde acaba el apellido: no se inventa. El caso de
    /// uso lo cuenta entre los de nombre que no vale, como lo escribe la federación ([D-120]).
    @Test("un nombre sin coma, con dos o con una mitad vacía no se vuelve: sin nombre, y con el publicado",
          arguments: ["GARCÍA LÓPEZ JUAN", "GARCÍA, LÓPEZ, JUAN", "GARCÍA LÓPEZ, ", ", JUAN", ""])
    func doesNotGuess(_ published: String) throws {
        let roster = try RFFMTeamSheetParser.parse(Self.names([published]))

        #expect(roster.players.count == 1)
        #expect(roster.players.first?.fullName == nil)
        #expect(roster.players.first?.publishedName == published)
    }

    /// `D-126`: el código de cada jugador, el mismo que en el acta. Con él se casa primero. Vacío, nulo: no se
    /// inventa.
    @Test("cada jugador, con su código en la federación; sin código, nulo (D-126)")
    func readsTheFederationCode() throws {
        let roster = try RFFMTeamSheetParser.parse(try Self.fixture())
        #expect(roster.players.first?.federationPlayerID == "90000001")
        #expect(roster.players.allSatisfy { $0.federationPlayerID != nil })

        let sinCodigo = try RFFMTeamSheetParser.parse(Self.page(
            team: #"{"codigo_equipo":"821","jugadores_equipo":[{"cod_jugador":" ","nombre":"GIL, LEO"},{"nombre":"GIL, TEO"}]}"#))
        #expect(sinCodigo.players.map(\.federationPlayerID) == [nil, nil])
    }

    /// Medido en R6.14: hay fichas de equipo sin ningún jugador. No es un error de la página: lo que haga con
    /// eso la sincronización lo decide el caso de uso.
    @Test("una ficha sin jugadores es una plantilla vacía, no un error")
    func emptyRoster() throws {
        let roster = try RFFMTeamSheetParser.parse(Self.page(team: #"{"codigo_equipo":"1","jugadores_equipo":[]}"#))

        #expect(roster.players.isEmpty)
    }

    /// Medido en R6.14: a un código que no existe, la RFFM responde 200 con el equipo a `null`, como el
    /// calendario a una coordenada que no existe ([Anexo RFFM §F.18]).
    @Test("un código que no existe: 200 con el equipo a null, es coordinateNotFound")
    func unknownCode() throws {
        #expect {
            try RFFMTeamSheetParser.parse(Self.page(team: "null"))
        } throws: { error in
            guard case FederationError.coordinateNotFound = error else { return false }
            return true
        }
    }

    @Test("un equipo sin la lista de jugadores, o una página que no es de la RFFM, es malformedResponse",
          arguments: [page(team: #"{"codigo_equipo":"821"}"#), "<html><body>Mantenimiento</body></html>"])
    func malformed(_ body: String) throws {
        #expect {
            try RFFMTeamSheetParser.parse(body)
        } throws: { error in
            guard case FederationError.malformedResponse = error else { return false }
            return true
        }
    }

    // ── La dirección ──

    @Test("la ficha de equipo, con el código de la inscripción")
    func buildsTheURL() {
        #expect(RFFMEndpoints().teamSheet(federationTeamID: "821") == "https://www.rffm.es/fichaequipo/821")
        #expect(RFFMEndpoints(baseURL: "http://localhost:8090").teamSheet(federationTeamID: "3349086")
                == "http://localhost:8090/fichaequipo/3349086")
    }

    @Test("el cliente pide la ficha de ese código y lee lo que llega")
    func clientFetches() async throws {
        let transport = RFFMFederationClientTests.SpyTransport(returning: .success(try Self.fixture()))
        let client = RFFMFederationClient(transport: transport)

        let roster = try await client.fetchTeamRoster(federationTeamID: "821")

        #expect(transport.requested == ["https://www.rffm.es/fichaequipo/821"])
        #expect(roster.players.count == 24)
    }

    // ── Quién es quién (D-126) ──

    @Test("el conector de la RFFM casa primero por el código y, si no, por el nombre (D-126)")
    func clientMatchesByCodeThenName() throws {
        let client = RFFMFederationClient(transport: RFFMFederationClientTests.SpyTransport(returning: .success("")))
        let juan = FederationMatchCandidate(
            profileID: PlayerProfileID(raw: UUID()), fullName: try PlayerName("Juanito Pérez"), federationPlayerID: "1")
        let ana = FederationMatchCandidate(
            profileID: PlayerProfileID(raw: UUID()), fullName: try PlayerName("Ana Ruiz"), federationPlayerID: nil)

        let matches = client.matchPlayers([
            FederationMatchQuery(federationPlayerID: "1", name: try PlayerName("JUAN PÉREZ")),
            FederationMatchQuery(federationPlayerID: "2", name: try PlayerName("ANA RUIZ")),
        ], against: [juan, ana])

        #expect(matches == [.byCode(juan.profileID), .byName(ana.profileID)])
    }
}
