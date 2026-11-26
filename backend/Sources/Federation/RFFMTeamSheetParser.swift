public import struct Application.FederationTeamRoster
import struct Application.FederationRosterPlayer
import enum Application.FederationError
import struct Foundation.Data
import class Foundation.JSONDecoder

/// De la ficha de equipo de la RFFM (`fichaequipo/<código>`) a la plantilla que el
/// puerto promete ([D-120], R6.14).
///
/// **Función pura**, como sus hermanos: entra la página, sale la plantilla.
///
/// # Lo medido (R6.14, con dos equipos del desarrollador y tres códigos más)
///
/// - Es una **página**, como el calendario: los datos van en el `__NEXT_DATA__`, en
///   `props.pageProps.team`. Por cada jugador, **solo su código y su nombre**, como
///   «APELLIDOS, NOMBRE» en mayúsculas (`jugadores_equipo`). El código es el mismo
///   que en el acta (`D-126`).
/// - **No dice de qué temporada es**: es la plantilla de hoy (decisión 1 de R6.14).
/// - A un **código que no existe**, `200` con `team: null`: como el calendario a una
///   coordenada que no existe, es `coordinateNotFound` y no un fallo de forma.
/// - **Hay fichas sin jugadores** (lista vacía): es una plantilla vacía, no un error.
///   Qué hacer con ella lo decide el caso de uso.
///
/// # Solo se da la vuelta por la coma
///
/// «GARCÍA DE LA FUENTE, JUAN CARLOS» → «JUAN CARLOS GARCÍA DE LA FUENTE» (plan R6,
/// decisión 9). Con **exactamente una** coma y las dos mitades con algo; si no, el
/// nombre se queda sin volver (`fullName` nulo) y el caso de uso lo cuenta entre los
/// que no valen, **como lo escribe la federación**. No se adivina dónde acaba el
/// apellido. Que el nombre vuelto sea válido lo mira el dominio (`PlayerName`).
public enum RFFMTeamSheetParser {

    public static func parse(_ html: String) throws -> FederationTeamRoster {
        let json = try NextDataExtractor.json(from: html)
        let page: Page
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            page = try decoder.decode(Page.self, from: Data(json.utf8))
        } catch {
            throw FederationError.malformedResponse(
                field: "props.pageProps.team",
                reason: "la ficha de equipo no tiene la forma medida: \(error)")
        }
        guard let team = page.props.pageProps.team else {
            throw FederationError.coordinateNotFound(
                detail: "la RFFM no tiene ningún equipo con ese código (ficha con el equipo a null)")
        }
        return FederationTeamRoster(players: team.jugadoresEquipo.map {
            FederationRosterPlayer(
                publishedName: $0.nombre, fullName: flipped($0.nombre),
                federationPlayerID: $0.codJugador.map { $0.trimmingCharacters(in: .whitespaces) }
                    .flatMap { $0.isEmpty ? nil : $0 })
        })
    }

    /// «APELLIDOS, NOMBRE» → «NOMBRE APELLIDOS», sin los espacios de los lados de
    /// cada mitad. Nulo si no hay exactamente una coma, o si una mitad está vacía.
    static func flipped(_ published: String) -> String? {
        let halves = published.split(separator: ",", omittingEmptySubsequences: false)
        guard halves.count == 2 else { return nil }
        let surnames = halves[0].trimmingCharacters(in: .whitespaces)
        let given = halves[1].trimmingCharacters(in: .whitespaces)
        guard !surnames.isEmpty, !given.isEmpty else { return nil }
        return "\(given) \(surnames)"
    }

    // Lo que se lee de la página, y nada más.
    private struct Page: Decodable {
        let props: Props
    }
    private struct Props: Decodable {
        let pageProps: PageProps
    }
    private struct PageProps: Decodable {
        // Optional: a un código que no existe llega `null`.
        let team: Team?
    }
    private struct Team: Decodable {
        let jugadoresEquipo: [Player]
    }
    private struct Player: Decodable {
        let nombre: String
        /// El código del jugador (`D-126`). Opcional: si un día no viene, se casa por el nombre.
        let codJugador: String?
    }
}
