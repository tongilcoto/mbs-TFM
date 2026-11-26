public import Application

/// **Solo para los dobles de las pruebas**: la plantilla publicada ([D-120], R6.14)
/// por defecto, para que los dobles de la ingesta, que no la usan, no tengan que
/// escribirla. Lanza si alguien la llama sin haberla preparado.
///
/// En producción el puerto **no** tiene implementación por defecto, y es a
/// propósito (ver `FederationClient.fetchTeamRoster`). Esta pieza no viaja al
/// binario de producción. Está repetida en `ApplicationTests`, que no depende de
/// ella.
extension FederationClient {
    public func fetchTeamRoster(federationTeamID: String) async throws -> FederationTeamRoster {
        throw FederationError.coordinateNotFound(detail: "doble sin plantilla: \(federationTeamID)")
    }

    /// Casar como la RFFM (`D-126`): los dobles no lo reescriben, y así casan de verdad.
    public func matchPlayers(
        _ published: [FederationMatchQuery], against ours: [FederationMatchCandidate]
    ) -> [FederationPlayerMatch] {
        FederationPlayerMatching.byCodeThenName(published, against: ours)
    }

    /// Lo mismo con el acta del partido (`D-125`, R7.11).
    public func fetchMatchReport(federationMatchID: String) async throws -> FederationMatchReport {
        throw FederationError.coordinateNotFound(detail: "doble sin acta: \(federationMatchID)")
    }
}
