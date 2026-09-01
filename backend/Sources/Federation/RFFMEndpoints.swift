public import struct Application.FederationCoordinate
public import enum Domain.Modality

/// Dónde vive cada cosa en la RFFM ([Anexo RFFM §F.1], §F.7).
///
/// **Un sitio y solo uno donde se escriben estas URLs.** El anexo insiste en que
/// los nombres de parámetro no se supongan: el del calendario es `grupo` y no
/// `codgrupo`, y `idGroup` —el de la clasificación— es **el único en *camelCase***
/// de toda la API. Tenerlos dispersos por el adaptador es pedir que alguien
/// "corrija" uno por simetría.
public enum RFFMEndpoints {
    static let host = "https://www.rffm.es"

    /// El calendario completo de un grupo: **una sola petición** (§5.6).
    ///
    /// Los cuatro parámetros de §F.1 son **jerárquicos y descompuestos**, no un
    /// identificador opaco. Tres salen de la coordenada del modelo (`D-74`) y el
    /// `tipojuego` se deriva de la modalidad, que no se almacena (§3.2, `D-07`).
    public static func calendar(for coordinate: FederationCoordinate) -> String {
        "\(host)/competicion/calendario"
            + "?temporada=\(coordinate.federationSeasonID)"
            + "&tipojuego=\(RFFMGameType.code(for: coordinate.modality))"
            + "&competicion=\(coordinate.federationCompetitionID)"
            + "&grupo=\(coordinate.federationGroupID)"
    }

    /// La **inversa**: la coordenada que hay dentro de una URL de calendario.
    ///
    /// # Por qué existe, y por qué no pide los números sueltos
    ///
    /// `D-22` fija la mitigación contra el dígito mal tecleado: **se pega la URL
    /// entera**, porque copiar de la barra de direcciones no admite errata. Una
    /// herramienta que pidiera los cuatro números por separado tiraría esa
    /// mitigación justo donde más cuesta — un dígito cambiado **no da error**,
    /// sincroniza otro calendario en silencio (`D-84`).
    ///
    /// # Y lo que falta se rechaza, no se completa
    ///
    /// Ningún valor por defecto: inventar una `temporada` ausente sería elegir
    /// por el administrador **cuál** de los calendarios reutilizados se ingiere.
    public static func coordinate(fromCalendarURL url: String) throws -> FederationCoordinate {
        let query = url.split(separator: "?").last.map(String.init) ?? ""
        var values: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { values[String(parts[0])] = String(parts[1]) }
        }

        func require(_ name: String) throws -> String {
            guard let value = values[name], !value.isEmpty else {
                throw RFFMURLError.missingParameter(name: name, url: url)
            }
            return value
        }

        let gameType = try require("tipojuego")
        guard let modality = RFFMGameType.modality(for: gameType) else {
            throw RFFMURLError.unknownGameType(gameType)
        }

        return FederationCoordinate(
            federationSeasonID: try require("temporada"),
            federationCompetitionID: try require("competicion"),
            federationGroupID: try require("grupo"),
            modality: modality)
    }
}

/// El `tipojuego` de la RFFM, desde la modalidad de dominio ([Anexo RFFM §F.9]).
///
/// **El `switch` es exhaustivo a propósito**: una modalidad nueva en §3.3 no
/// compila hasta que alguien decida su código, que es el mismo criterio con el que
/// `FederationCode.toContract()` sostiene el catálogo de federaciones.
///
/// > **La correspondencia no sigue el orden del enumerado, y ahí está la trampa:**
/// > `3` es **fútbol sala** y `4` es **fútbol-5**. Escribirlo "por orden" no daría
/// > un 404 — devolvería el calendario de **otra modalidad**, en silencio.
public enum RFFMGameType {
    /// La vuelta del `switch` de abajo, **derivada de él y no tecleada aparte**:
    /// dos tablas a mano se desincronizan, y aquí desincronizarse significa
    /// ingerir la modalidad equivocada sin error.
    public static func modality(for code: String) -> Modality? {
        Modality.allCases.first { Self.code(for: $0) == code }
    }

    public static func code(for modality: Modality) -> String {
        switch modality {
        case .futbol11: "1"
        case .futbol7: "2"
        case .futbolSala: "3"
        case .futbol5: "4"
        case .futbolPlaya: "5"
        }
    }
}


/// Lo que una URL de calendario puede tener mal.
public enum RFFMURLError: Error, CustomStringConvertible, Equatable {
    case missingParameter(name: String, url: String)
    case unknownGameType(String)

    public var description: String {
        switch self {
        case .missingParameter(let name, let url):
            "A la URL le falta el parámetro '\(name)': \(url)"
        case .unknownGameType(let code):
            "`tipojuego=\(code)` no está en el catálogo ([Anexo RFFM §F.9])."
        }
    }
}
