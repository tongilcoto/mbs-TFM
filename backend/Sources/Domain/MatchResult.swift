/// El marcador de un partido (§4.1).
///
/// **Los dos goles juntos o ninguno**: un partido no puede tener marcador a
/// medias, así que `Match.result` es un `MatchResult?` y no dos enteros
/// anulables sueltos. Eso es además lo que convierte *"¿se ha jugado?"* en una
/// pregunta con una sola respuesta, y de ella depende la desambiguación del
/// horario vacío (`D-56`).
///
/// Ojo con el vacío de la fuente: `""` y `"0"` **no son intercambiables**
/// ([Anexo RFFM §F.11]), y en la FCF un partido sin jugar trae `"0"` y lo que lo
/// distingue es otro campo ([Anexo FCF §C.10.5]). Traducir eso es tarea del
/// adaptador; lo que aquí llega es `nil` o un marcador.
public struct MatchResult: Equatable, Sendable {
    public let homeScore: Int
    public let awayScore: Int

    public init(homeScore: Int, awayScore: Int) throws {
        guard homeScore >= 0, awayScore >= 0 else {
            throw DomainError.invalidValue(
                field: "score", reason: "un marcador no puede ser negativo"
            )
        }
        self.homeScore = homeScore
        self.awayScore = awayScore
    }
}
