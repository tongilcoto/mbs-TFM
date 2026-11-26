public import struct Application.FederationMatchReport
import struct Application.FederationReportPlayer
import struct Application.FederationReportGoal
import struct Application.FederationReportCard
import struct Application.FederationReportSkip
import enum Application.FederationReportSide
import enum Application.FederationError
import enum Domain.CardType
import enum Domain.GoalPlayType
import struct Foundation.Data
import class Foundation.JSONDecoder

/// Del acta de un partido de la RFFM (`acta-partido/<codacta>`) al acta que el puerto promete (`D-125`, `D-131`,
/// R7.11).
///
/// **Función pura**, como sus hermanos: entra la página, sale el acta, ya en nuestros tipos.
///
/// # Lo medido (R7.1 en 91 actas; R7.11 en las 96 cerradas del club, una sin cerrar y un código que no existe)
///
/// - Es una **página**, como el calendario y la ficha: los datos van en el `__NEXT_DATA__`, en
///   `props.pageProps.game`. Todo llega como cadena (§F.11).
/// - **Antes de firmarse**, la página existe con `acta_cerrada = 0`, sin marcador y sin jugadores (`D-133`).
/// - **A un código que no existe**, `200` y un acta con todo vacío, **sin códigos de equipo**: no llega `null`, como
///   en la ficha. Es `coordinateNotFound`.
/// - **Los goles**, en la lista del equipo del jugador: `100` normal, `101` penalti, `102` en propia puerta. El de
///   propia puerta suma al otro equipo, y así el marcador cuadra (las 3 actas con uno).
/// - **Las tarjetas**: `100` amarilla, `101` roja; la doble amarilla, dos `100` del mismo jugador, la segunda con
///   `segunda_amarilla = "1"`.
/// - **Los cambios**, con el código del que entra (`codjugador_entra`).
///
/// # Lo que no se lee
///
/// `goles_penalti` y `otras_tarjetas` llegan vacías en todas las actas medidas (la tanda de penaltis y, por el
/// nombre, las de fuera del campo); el cuerpo técnico, los árbitros y la `participacion`, que no se usa (`D-132`).
public enum RFFMMatchReportParser {

    public static func parse(_ html: String) throws -> FederationMatchReport {
        let json = try NextDataExtractor.json(from: html)
        let page: Page
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            page = try decoder.decode(Page.self, from: Data(json.utf8))
        } catch {
            throw FederationError.malformedResponse(
                field: "props.pageProps.game",
                reason: "el acta no tiene la forma medida: \(error)")
        }
        guard let game = page.props.pageProps.game else {
            throw FederationError.malformedResponse(
                field: "props.pageProps.game", reason: "la página no trae acta")
        }
        let home = text(game.codigoEquipoLocal)
        let away = text(game.codigoEquipoVisitante)
        guard !home.isEmpty, !away.isEmpty else {
            throw FederationError.coordinateNotFound(
                detail: "la RFFM no tiene ningún acta con el código \(text(game.codacta)) (acta sin equipos)")
        }

        var skipped: [FederationReportSkip] = []
        let players = try readPlayers(game.jugadoresEquipoLocal, changes: game.sustitucionesEquipoLocal, .home)
            + readPlayers(game.jugadoresEquipoVisitante, changes: game.sustitucionesEquipoVisitante, .away)
        let goals = try readGoals(game.golesEquipoLocal, .home, &skipped)
            + readGoals(game.golesEquipoVisitante, .away, &skipped)
        let cards = try readCards(game.tarjetasEquipoLocal, .home, &skipped)
            + readCards(game.tarjetasEquipoVisitante, .away, &skipped)

        return FederationMatchReport(
            isClosed: text(game.actaCerrada) == "1",
            homeTeamFederationID: home, awayTeamFederationID: away,
            homeScore: try RFFMValue.score(game.golesLocal), awayScore: try RFFMValue.score(game.golesVisitante),
            players: players, goals: goals, cards: cards, skipped: skipped)
    }

    // ── Los jugadores ──

    private static func readPlayers(
        _ list: [Player]?, changes: [Change]?, _ side: FederationReportSide
    ) throws -> [FederationReportPlayer] {
        let cameOn = Set((changes ?? []).map { text($0.codjugadorEntra) })
        return try (list ?? []).map { player in
            let code = text(player.codjugador)
            let name = player.nombreJugador ?? ""
            return FederationReportPlayer(
                side: side, federationPlayerID: code, publishedName: name,
                fullName: RFFMTeamSheetParser.flipped(name),
                shirtNumber: try number(player.dorsal, field: "jugadores_equipo.dorsal"),
                isStarter: text(player.titular) == "1", cameOn: cameOn.contains(code))
        }
    }

    // ── Los goles (D-131, puntos 1, 2 y 4) ──

    private static func readGoals(
        _ list: [Goal]?, _ listSide: FederationReportSide, _ skipped: inout [FederationReportSkip]
    ) throws -> [FederationReportGoal] {
        try (list ?? []).compactMap { goal in
            let code = text(goal.tipoGol)
            let playType: GoalPlayType?
            var side = listSide
            switch code {
            case "100": playType = nil
            case "101": playType = .penalti
            case "102":
                playType = .enPropiaPuerta
                side = listSide == .home ? .away : .home
            default:
                skipped.append(FederationReportSkip(kind: .goal, side: listSide, code: code))
                return nil
            }
            return FederationReportGoal(
                side: side, federationPlayerID: text(goal.codjugador), publishedName: goal.nombreJugador ?? "",
                minute: try number(goal.minuto, field: "goles.minuto"), playType: playType)
        }
    }

    // ── Las tarjetas (D-131, puntos 3 y 4) ──

    private static func readCards(
        _ list: [Card]?, _ side: FederationReportSide, _ skipped: inout [FederationReportSkip]
    ) throws -> [FederationReportCard] {
        let list = list ?? []
        // La primera amarilla de quien ve la segunda no es una sanción aparte: no acumula (`D-10`, `D-45`).
        let doubled = Set(list.filter(isSecondYellow).map { text($0.codjugador) })
        var firstYellowDropped = Set<String>()
        var cards: [FederationReportCard] = []
        for card in list {
            let code = text(card.codigoTipoAmonestacion)
            let player = text(card.codjugador)
            let type: CardType
            switch code {
            case "100" where isSecondYellow(card): type = .roja
            case "100" where doubled.contains(player) && !firstYellowDropped.contains(player):
                firstYellowDropped.insert(player)
                continue
            case "100": type = .amarilla
            case "101" where !isSecondYellow(card): type = .roja
            default:
                skipped.append(FederationReportSkip(kind: .card, side: side, code: code))
                continue
            }
            cards.append(FederationReportCard(
                side: side, federationPlayerID: player, publishedName: card.nombreJugador ?? "",
                minute: try number(card.minuto, field: "tarjetas.minuto"), type: type,
                isSecondYellow: isSecondYellow(card)))
        }
        return cards
    }

    private static func isSecondYellow(_ card: Card) -> Bool { text(card.segundaAmarilla) == "1" }

    // ── Los valores ──

    private static func text(_ raw: String?) -> String { (raw ?? "").trimmingCharacters(in: .whitespaces) }

    /// Un minuto o un dorsal: vacío es «no lo dice» (§F.11), no un cero.
    private static func number(_ raw: String?, field: String) throws -> Int? {
        let cleaned = text(raw)
        guard !cleaned.isEmpty else { return nil }
        guard let value = Int(cleaned), value >= 0 else {
            throw FederationError.malformedResponse(field: field, reason: #"no es un número: "\#(cleaned)""#)
        }
        return value
    }

    // ── Lo que se lee de la página, y nada más ──

    private struct Page: Decodable {
        let props: Props
    }
    private struct Props: Decodable {
        let pageProps: PageProps
    }
    private struct PageProps: Decodable {
        let game: Game?
    }
    private struct Game: Decodable {
        let codacta: String?
        let actaCerrada: String?
        let codigoEquipoLocal: String?
        let codigoEquipoVisitante: String?
        let golesLocal: String?
        let golesVisitante: String?
        let jugadoresEquipoLocal: [Player]?
        let jugadoresEquipoVisitante: [Player]?
        let golesEquipoLocal: [Goal]?
        let golesEquipoVisitante: [Goal]?
        let tarjetasEquipoLocal: [Card]?
        let tarjetasEquipoVisitante: [Card]?
        let sustitucionesEquipoLocal: [Change]?
        let sustitucionesEquipoVisitante: [Change]?
    }
    private struct Player: Decodable {
        let codjugador: String?
        let nombreJugador: String?
        let dorsal: String?
        let titular: String?
    }
    private struct Goal: Decodable {
        let codjugador: String?
        let nombreJugador: String?
        let minuto: String?
        let tipoGol: String?
    }
    private struct Card: Decodable {
        let codigoTipoAmonestacion: String?
        let codjugador: String?
        let segundaAmarilla: String?
        let minuto: String?
        let nombreJugador: String?
    }
    private struct Change: Decodable {
        let codjugadorEntra: String?
    }
}
