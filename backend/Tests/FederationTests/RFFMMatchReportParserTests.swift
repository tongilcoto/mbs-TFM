import Foundation
import Testing
import Application
import Domain
@testable import Federation

/// Nivel 1 (§8.1), **sin red**: el acta de un partido de la RFFM (`acta-partido/<codacta>`), de donde sale lo que la
/// carga del acta escribe (`D-125`, `D-131`, R7.11). Contra tres grabaciones de verdad —dos con los datos personales
/// cambiados (`Tools/Fixtures/anonymize-rffm-match-report.swift`) y la de un acta sin cerrar, que no trae a nadie—,
/// la de un código que no existe, y páginas mínimas para lo que las grabaciones no enseñan.
@Suite("RFFMMatchReportParser · D-131 · el acta del partido")
struct RFFMMatchReportParserTests {

    static func fixture(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "html"),
            "no encuentro la grabación \(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func withCards() throws -> FederationMatchReport {
        try RFFMMatchReportParser.parse(try fixture("RFFM-acta-penalti-roja-segunda-amarilla"))
    }

    static func withOwnGoal() throws -> FederationMatchReport {
        try RFFMMatchReportParser.parse(try fixture("RFFM-acta-propia-puerta"))
    }

    /// Una página como la de la RFFM, con solo lo que lee el lector: un acta cerrada, 1-0, con lo que se le pase.
    static func page(
        homeGoals: String = "[]", awayGoals: String = "[]", homeCards: String = "[]",
        homePlayers: String = #"[{"codjugador":"11","dorsal":"7","nombre_jugador":"GIL, LEO","titular":"1","suplente":"0"}]"#,
        closed: String = "1", homeScore: String = "1", awayScore: String = "0", homeTeam: String = "821"
    ) -> String {
        let game = """
            {"codacta":"1","acta_cerrada":"\(closed)","codigo_equipo_local":"\(homeTeam)",\
            "codigo_equipo_visitante":"900","goles_local":"\(homeScore)","goles_visitante":"\(awayScore)",\
            "jugadores_equipo_local":\(homePlayers),"jugadores_equipo_visitante":[],\
            "goles_equipo_local":\(homeGoals),"goles_equipo_visitante":\(awayGoals),\
            "tarjetas_equipo_local":\(homeCards),"tarjetas_equipo_visitante":[],\
            "sustituciones_equipo_local":[],"sustituciones_equipo_visitante":[]}
            """
        return """
            <html><body><div id="__next"></div>
            <script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"game":\(game)}},"page":"/acta-partido/[codacta]"}</script>
            </body></html>
            """
    }

    static func goal(_ code: String, minute: String = "10", player: String = "11") -> String {
        #"{"codjugador":"\#(player)","nombre_jugador":"GIL, LEO","minuto":"\#(minute)","tipo_gol":"\#(code)"}"#
    }

    static func card(_ code: String, secondYellow: String = "0", minute: String = "30", player: String = "11")
        -> String
    {
        #"{"codigo_tipo_amonestacion":"\#(code)","codjugador":"\#(player)","segunda_amarilla":"\#(secondYellow)","minuto":"\#(minute)","nombre_jugador":"GIL, LEO"}"#
    }

    // ── El acta sin cerrar y la que no existe ──

    /// Medido en R7.1 (decisión 11): la página del acta existe antes del partido, con `acta_cerrada = 0`, sin
    /// marcador y sin jugadores. No es un error: es un acta que todavía no se carga (`D-133`).
    @Test("el acta sin cerrar: no cerrada, sin marcador y sin nadie, pero con los dos equipos")
    func readsTheOpenReport() throws {
        let report = try RFFMMatchReportParser.parse(try Self.fixture("RFFM-acta-sin-cerrar"))

        #expect(report.isClosed == false)
        #expect(report.homeTeamFederationID == "8956087")
        #expect(report.awayTeamFederationID == "820")
        #expect(report.homeScore == nil)
        #expect(report.awayScore == nil)
        #expect(report.players.isEmpty)
        #expect(report.goals.isEmpty)
        #expect(report.cards.isEmpty)
    }

    /// Medido en R7.11: a un código que no existe, `200` y un acta con todo vacío. No llega `null`, como en la
    /// ficha o el calendario: lo que la delata es que **no tiene equipos**. Es `coordinateNotFound`, no un acta.
    @Test("un código de acta que no existe: coordinateNotFound, no un acta vacía")
    func missingReportIsNotFound() throws {
        let page = try Self.fixture("RFFM-acta-inexistente")

        #expect {
            try RFFMMatchReportParser.parse(page)
        } throws: { error in
            guard case .coordinateNotFound = error as? FederationError else { return false }
            return true
        }
    }

    @Test("una página sin acta, o con un acta sin la forma medida: malformedResponse")
    func malformed() throws {
        let noGame = #"<script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{}}}</script>"#
        let badList = Self.page(homeGoals: #""ninguno""#)

        for page in [noGame, badList] {
            #expect {
                try RFFMMatchReportParser.parse(page)
            } throws: { error in
                guard case .malformedResponse = error as? FederationError else { return false }
                return true
            }
        }
    }

    // ── El acta cerrada: los equipos, el marcador y los jugadores ──

    @Test("el acta cerrada: los dos equipos y el marcador")
    func readsTheHeader() throws {
        let report = try Self.withCards()

        #expect(report.isClosed)
        #expect(report.homeTeamFederationID == "3349086")
        #expect(report.awayTeamFederationID == "699")
        #expect(report.homeScore == 1)
        #expect(report.awayScore == 2)
    }

    @Test("los 35 jugadores, primero los del local, cada uno con su código, su nombre vuelto y su dorsal; el primero, el portero suplente")
    func readsThePlayers() throws {
        let players = try Self.withCards().players

        #expect(players.count == 35)
        #expect(players.prefix(18).allSatisfy { $0.side == .home })
        #expect(players.suffix(17).allSatisfy { $0.side == .away })
        #expect(players.first == FederationReportPlayer(
            side: .home, federationPlayerID: "9000001", publishedName: "GARCÍA LÓPEZ, JUAN CARLOS",
            fullName: "JUAN CARLOS GARCÍA LÓPEZ", shirtNumber: 1, isStarter: false, cameOn: false))
        #expect(players.allSatisfy { $0.shirtNumber != nil }, "el acta trae el dorsal de todos (432/432, R7.1)")
    }

    /// `D-132`, punto 2: jugó quien es titular o entra en un cambio. Los 11 titulares de cada lado, y los 7 que
    /// entran en los 7 cambios del acta, todos suplentes.
    @Test("titulares y los que entran en un cambio: 11 y 11 titulares; 4 y 3 que entran, suplentes")
    func readsWhoCameOn() throws {
        let players = try Self.withCards().players

        #expect(players.filter { $0.side == .home && $0.isStarter }.count == 11)
        #expect(players.filter { $0.side == .away && $0.isStarter }.count == 11)
        #expect(players.filter { $0.side == .home && $0.cameOn }.count == 4)
        #expect(players.filter { $0.side == .away && $0.cameOn }.count == 3)
        #expect(players.filter(\.cameOn).allSatisfy { !$0.isStarter })
    }

    // ── Los goles (D-131, puntos 1 y 2) ──

    @Test("el gol normal, sin tipo; el 101, penalti; cada uno con su lado, su jugador y su minuto")
    func readsTheGoals() throws {
        let goals = try Self.withCards().goals

        #expect(goals.count == 3)
        #expect(goals.first == FederationReportGoal(
            side: .home, federationPlayerID: "9000009", publishedName: "MARTÍNEZ SOTO, ADRIÁN", minute: 17,
            playType: .penalti))
        #expect(goals.filter { $0.side == .away }.map(\.playType) == [nil, nil])
        #expect(goals.filter { $0.side == .away }.map(\.minute) == [8, 25])
    }

    /// La RFFM pone el gol en propia puerta en la lista del equipo del jugador que lo marca (medido en las tres
    /// actas con uno de las 96 del club): **suma al otro**. En el acta grabada, uno del visitante en el 31.
    @Test("el gol en propia puerta: del jugador del visitante, y suma al local")
    func readsTheOwnGoal() throws {
        let goals = try Self.withOwnGoal().goals

        let ownGoal = try #require(goals.first { $0.playType == .enPropiaPuerta })
        #expect(ownGoal == FederationReportGoal(
            side: .home, federationPlayerID: "90000032", publishedName: "CORTÉS PAREDES, LUIS MIGUEL", minute: 31,
            playType: .enPropiaPuerta))
        #expect(try Self.withOwnGoal().players.first { $0.federationPlayerID == "90000032" }?.side == .away)
    }

    /// Leído así, el marcador cuadra (90 de 91 en R7.1; la otra, el 0-3 sin goles de una sanción).
    @Test("los goles de cada lado son su marcador, en las dos actas cerradas",
          arguments: ["RFFM-acta-penalti-roja-segunda-amarilla", "RFFM-acta-propia-puerta"])
    func goalsAddUpToTheScore(_ name: String) throws {
        let report = try RFFMMatchReportParser.parse(try Self.fixture(name))

        #expect(report.goals.filter { $0.side == .home }.count == report.homeScore)
        #expect(report.goals.filter { $0.side == .away }.count == report.awayScore)
    }

    // ── Las tarjetas (D-131, punto 3) ──

    /// 10 tarjetas en la página: 8 amarillas, una roja directa y una segunda amarilla del jugador que ya tenía
    /// otra. Son 9 sanciones: la doble amarilla es **una** roja, y su primera amarilla no viene aparte (`D-45`).
    @Test("la doble amarilla, una sola roja con isSecondYellow y sin su primera amarilla: 9 sanciones de 10")
    func readsTheSecondYellow() throws {
        let cards = try Self.withCards().cards

        #expect(cards.count == 9)
        let doubled = cards.filter { $0.federationPlayerID == "900010" }
        #expect(doubled == [FederationReportCard(
            side: .home, federationPlayerID: "900010", publishedName: "RODRÍGUEZ PEÑA, LUCAS", minute: 65,
            type: .roja, isSecondYellow: true)])
    }

    @Test("el 101, roja directa; el 100, amarilla")
    func readsTheCardCodes() throws {
        let cards = try Self.withCards().cards

        let reds = cards.filter { $0.type == .roja && !$0.isSecondYellow }
        #expect(reds.map(\.publishedName) == ["CORTÉS PAREDES, LUIS MIGUEL"])
        #expect(reds.map(\.side) == [.away])
        #expect(reds.map(\.minute) == [50])
        #expect(cards.filter { $0.type == .amarilla }.count == 7)
        #expect(cards.filter { $0.type == .amarilla }.allSatisfy { !$0.isSecondYellow })
    }

    // ── Lo que las grabaciones no enseñan ──

    /// `D-131`, punto 4: un código que no es ninguno de los medidos no se adivina. El apunte no sale, y se cuenta.
    @Test("un gol o una tarjeta con un código que no se conoce: fuera, y contado en skipped")
    func skipsUnknownCodes() throws {
        let report = try RFFMMatchReportParser.parse(Self.page(
            homeGoals: "[\(Self.goal("103")), \(Self.goal("100"))]", homeCards: "[\(Self.card("102"))]"))

        #expect(report.goals.map(\.playType) == [nil])
        #expect(report.cards.isEmpty)
        #expect(report.skipped == [
            FederationReportSkip(kind: .goal, side: .home, code: "103"),
            FederationReportSkip(kind: .card, side: .home, code: "102"),
        ])
    }

    /// La segunda amarilla sin la primera en el acta: sigue siendo la roja por doble amarilla.
    @Test("una segunda amarilla sin la primera: una roja con isSecondYellow")
    func secondYellowAlone() throws {
        let report = try RFFMMatchReportParser.parse(Self.page(
            homeCards: "[\(Self.card("100", secondYellow: "1"))]"))

        #expect(report.cards.map(\.type) == [.roja])
        #expect(report.cards.map(\.isSecondYellow) == [true])
    }

    /// La doble amarilla solo se lleva la amarilla del mismo jugador: la de otro se queda.
    @Test("la doble amarilla no se lleva la amarilla de otro jugador")
    func secondYellowKeepsOthers() throws {
        let report = try RFFMMatchReportParser.parse(Self.page(homeCards: """
            [\(Self.card("100", minute: "20", player: "22")), \(Self.card("100", minute: "25")), \
            \(Self.card("100", secondYellow: "1", minute: "60"))]
            """))

        #expect(report.cards.map(\.federationPlayerID) == ["22", "11"])
        #expect(report.cards.map(\.type) == [.amarilla, .roja])
    }

    /// Como el marcador en el calendario: lo vacío es «no lo sé», no un cero (§F.11).
    @Test("sin minuto ni dorsal: nulos, no cero")
    func emptyValuesAreNil() throws {
        let report = try RFFMMatchReportParser.parse(Self.page(
            homeGoals: "[\(Self.goal("100", minute: ""))]",
            homePlayers: #"[{"codjugador":"11","dorsal":"","nombre_jugador":"GIL, LEO","titular":"0","suplente":"1"}]"#))

        #expect(report.goals.first?.minute == nil)
        #expect(report.players.first?.shirtNumber == nil)
        #expect(report.players.first?.isStarter == false)
    }

    @Test("un minuto o un dorsal que no son números: malformedResponse", arguments: ["diez", "1x"])
    func badNumbers(_ raw: String) throws {
        #expect {
            try RFFMMatchReportParser.parse(Self.page(homeGoals: "[\(Self.goal("100", minute: raw))]"))
        } throws: { error in
            guard case .malformedResponse = error as? FederationError else { return false }
            return true
        }
    }

    // ── La dirección ──

    /// Medido en R7.11: la página del acta responde igual con el código solo que con la temporada, la competición
    /// y el grupo detrás. El código del acta es el `federation_match_id` del partido (`D-31`), que trae el
    /// calendario. No se usa la ruta `_next/data/<versión>/…`: la versión cambia con cada despliegue de la RFFM.
    @Test("el acta, con el código del partido en la federación")
    func buildsTheURL() {
        #expect(RFFMEndpoints().matchReport(federationMatchID: "5589189") == "https://www.rffm.es/acta-partido/5589189")
        #expect(RFFMEndpoints(baseURL: "http://localhost:8090").matchReport(federationMatchID: "5670205")
                == "http://localhost:8090/acta-partido/5670205")
    }

    @Test("el cliente pide el acta de ese código y lee lo que llega")
    func clientFetches() async throws {
        let transport = RFFMFederationClientTests.SpyTransport(
            returning: .success(try Self.fixture("RFFM-acta-propia-puerta")))
        let client = RFFMFederationClient(transport: transport)

        let report = try await client.fetchMatchReport(federationMatchID: "5670205")

        #expect(transport.requested == ["https://www.rffm.es/acta-partido/5670205"])
        #expect(report.goals.count == 11)
    }
}
