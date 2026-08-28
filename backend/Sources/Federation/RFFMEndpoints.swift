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
