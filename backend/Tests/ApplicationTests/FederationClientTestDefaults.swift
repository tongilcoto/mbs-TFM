import Application
import Testing

/// **Solo para los dobles de las pruebas**: la plantilla publicada ([D-120], R6.14)
/// por defecto, para que los dobles de la ingesta, que no la usan, no tengan que
/// escribirla. Falla si alguien la llama sin haberla preparado.
///
/// En producción el puerto **no** tiene implementación por defecto, y es a
/// propósito (ver `FederationClient.fetchTeamRoster`). Está repetida en
/// `TestSupport` para las pruebas contra Postgres y de la API: esta batería no
/// depende de ella.
extension FederationClient {
    func fetchTeamRoster(federationTeamID: String) async throws -> FederationTeamRoster {
        Issue.record("este doble no prepara la plantilla publicada: \(federationTeamID)")
        throw FederationError.coordinateNotFound(detail: "doble sin plantilla")
    }

    /// Casar como la RFFM (`D-126`): los dobles no lo reescriben, y así casan de verdad.
    func matchPlayers(
        _ published: [FederationMatchQuery], against ours: [FederationMatchCandidate]
    ) -> [FederationPlayerMatch] {
        FederationPlayerMatching.byCodeThenName(published, against: ours)
    }

    /// Lo mismo con el acta del partido (`D-125`, R7.11).
    func fetchMatchReport(federationMatchID: String) async throws -> FederationMatchReport {
        Issue.record("este doble no prepara el acta: \(federationMatchID)")
        throw FederationError.coordinateNotFound(detail: "doble sin acta")
    }
}
