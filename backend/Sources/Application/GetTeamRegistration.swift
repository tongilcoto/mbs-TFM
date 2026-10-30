public import Domain

/// `GET /v1/teams/{teamId}/registrations/{seasonId}` (`D-102`, R4.5): **el
/// equipo en una temporada**, con sus competiciones. La misma forma que cada
/// elemento de `ListSeasonRegistrations`; es lo que pide la ficha del equipo del
/// backoffice.
public struct GetTeamRegistration: Sendable {
    private let clubs: any ClubRepository
    private let seasons: any SeasonRepository
    private let teams: any TeamRepository
    private let registrations: any TeamRegistrationRepository

    public init(
        clubs: any ClubRepository,
        seasons: any SeasonRepository,
        teams: any TeamRepository,
        registrations: any TeamRegistrationRepository
    ) {
        self.clubs = clubs
        self.seasons = seasons
        self.teams = teams
        self.registrations = registrations
    }

    public func execute(actor: ActorContext, teamID: TeamID, seasonID: SeasonID) async throws -> TeamInSeason {
        guard let club = try await clubs.current() else {
            throw ApplicationError.tenantNotProvisioned(slug: actor.clubSlug.value)
        }
        // Los dos ids los puso quien llama: si no existen, **404**, cada uno con
        // su código, como en `GetTeam` y `ListSeasonRegistrations`.
        guard let team = try await teams.find(teamID) else {
            throw ApplicationError.teamNotFound(id: "\(teamID)")
        }
        guard try await seasons.find(seasonID) != nil else {
            throw ApplicationError.unknownSeason(id: "\(seasonID)")
        }
        // Sin filas, no está inscrito; un rival nunca lo está (`D-68`), así que
        // no hace falta mirarlo aparte.
        let rows = try await registrations.list(teamID: teamID, seasonID: seasonID)
        guard !rows.isEmpty else {
            throw ApplicationError.teamNotRegistered(team: "\(teamID)", season: "\(seasonID)")
        }
        return TeamInSeason(club: club, registration: SeasonRegistration(team: team, seasonID: seasonID, rows: rows))
    }
}

/// Lo que devuelve `GetTeamRegistration`: la inscripción, y el club, porque la
/// respuesta del equipo dice de qué club es (`clubName`, `displayName`).
public struct TeamInSeason: Equatable, Sendable {
    public let club: Club
    public let registration: SeasonRegistration
}
