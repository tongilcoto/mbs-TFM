public import APIContract

/// `POST /v1/teams/{id}/federation-link/preview` y `POST /v1/teams/{id}/federation-link`
/// — los dos endpoints del enganche (`D-67`, F10).
///
/// # Esto es el ESQUELETO del Bloque 0, y está mal a propósito
///
/// `C-0.1` añade las dos operaciones al `filter` de
/// `openapi-generator-config.yaml`, que es el trinquete del alcance (`D-69`):
/// desde ese momento `APIProtocol` declara sus dos métodos y `APIHandler` **no
/// compila** hasta que existen. Los de abajo existen con su **firma
/// definitiva** y devuelven **un valor válido pero equivocado** — nunca
/// `fatalError()`, que trapea y se lleva la ejecución entera (Plan §5.1).
///
/// **Por qué nacen aquí y no en el Bloque E, que es el suyo.** Sin ellos el
/// *build* queda rojo desde `C-0.1` hasta `C-E.3`/`C-E.4`, y en esa ventana los
/// bloques A, B, C y D **no podrían correr la batería** — que es justo lo que el
/// método exige en cada ciclo. Un esqueleto cuesta un minuto y compra cuatro
/// bloques de rojo de aserción en vez de rojo de compilación.
///
/// **Lo que devuelven es deliberadamente reconocible como falso**: la coordenada
/// de ejemplo del *spec*, cero equipos y los UUID a ceros. Ningún dato de la
/// petición se mira. Si esto llega a una pantalla, se ve de lejos.
///
/// `C-E.3` y `C-E.4` los sustituyen por los de verdad. Hasta entonces, **no hay
/// test que los afirme**: un esqueleto no es una implementación a medias, es un
/// hueco con forma.
extension APIHandler {

    /// `C-E.3` lo convierte en el de verdad: **200 y no persiste nada**.
    public func previewFederationLink(_ input: Operations.previewFederationLink.Input) async throws
        -> Operations.previewFederationLink.Output
    {
        .ok(.init(body: .json(.init(
            season: .init(federationSeasonId: "0", label: "0000/00", exists: false),
            competition: .init(
                modality: .futbol_11,
                gender: .init(value1: .masculino),
                ageCategory: .senior,
                divisionLabel: "ESQUELETO",
                groupLabel: "ESQUELETO",
                federationCompetitionId: "0",
                federationGroupId: "0",
                roundCount: 0,
                teams: [],
                alreadyRegistered: false),
            identityMatches: false))))
    }

    /// `C-E.4` lo convierte en el de verdad: **202 con `IngestJobResponse`**, y
    /// con la fila `accepted` escrita **antes** de responder (`D-96`, `C-C.11`).
    public func linkTeamToFederation(_ input: Operations.linkTeamToFederation.Input) async throws
        -> Operations.linkTeamToFederation.Output
    {
        let nobody = "00000000-0000-0000-0000-000000000000"
        return .accepted(.init(body: .json(.init(
            jobId: nobody,
            status: .encolado,
            teamId: nobody,
            competitionId: nobody,
            seasonId: nobody))))
    }
}
