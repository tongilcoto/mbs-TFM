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
}
