public import Domain

/// **Quién del club tiene ya un código de equipo de la federación** (`D-110`).
///
/// Son las dos comprobaciones del 409 `FEDERATION_TEAM_ID_TAKEN` del enganche
/// (`C-E.10`), sacadas aquí para que el `/preview` avise con **la misma** regla y
/// no con una copia: si un día cambia lo que rechaza el enganche, cambia lo que
/// avisa el `/preview`. En el mismo orden:
///
/// 1. **Un rival de esta temporada** con ese código (`D-104`). Basta con que
///    exista la temporada: el código de un rival no es de una competición.
/// 2. **Un equipo propio sincronizado con ese código en esta competición**
///    (`D-101`), salvo el que se excluya. Sin competición no hay ninguno.
///
/// Se carga una vez y se pregunta por cada código: el `/preview` pregunta por
/// todos los equipos del grupo, y el enganche por uno.
struct FederationCodeHolders: Sendable {

    enum Holder: Equatable, Sendable {
        /// Un rival de esta temporada. Siempre lo es: un equipo propio no lleva
        /// código en `teams` (`D-101`, el `init` de `Team` lo impide).
        case opponent(Team)
        /// Un equipo propio, sincronizado en esta competición.
        case own(TeamID)

        var teamID: TeamID {
            switch self {
            case .opponent(let team): team.id
            case .own(let id): id
            }
        }
    }

    private let seasonID: SeasonID
    private let teams: [Team]
    private let registrations: [TeamRegistration]

    static func load(
        seasonID: SeasonID, competitionID: CompetitionID?, from repositories: any Repositories
    ) async throws -> FederationCodeHolders {
        var registrations: [TeamRegistration] = []
        if let competitionID {
            registrations = try await repositories.teamRegistrations.list(competitionID: competitionID)
        }
        return FederationCodeHolders(
            seasonID: seasonID,
            teams: try await repositories.teams.list(),
            registrations: registrations)
    }

    /// **`excluding`** es el equipo que se sincroniza: el enganche lo pasa, porque
    /// volver a sincronizarlo con su mismo código es idempotente; el `/preview`
    /// no, porque enseña que ya lo está (`D-110`, punto 3).
    func holder(of code: String, excluding teamID: TeamID?) -> Holder? {
        if let rival = teams.first(where: {
            $0.counts(in: seasonID) && $0.federationTeamID == code
        }) {
            return .opponent(rival)
        }
        if let row = registrations.first(where: {
            $0.federationTeamID == code && $0.teamID != teamID
        }) {
            return .own(row.teamID)
        }
        return nil
    }

    /// El equipo propio de un `.own`, de la lista ya cargada: el `/preview` lo
    /// necesita para rotularlo, y así no vuelve a pedirlo.
    func team(_ id: TeamID) -> Team? {
        teams.first { $0.id == id }
    }
}
