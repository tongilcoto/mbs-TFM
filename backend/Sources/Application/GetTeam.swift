public import Domain

/// `GET /v1/teams/{teamId}` (§5.1, R3.7): **un equipo del club, propio o rival**,
/// con el club del que sale su nombre.
///
/// El adaptador HTTP compone los derivados de `TeamResponse` (§3.6), y para eso
/// necesita el club: el propio si el equipo es del club, el rival si no.
public struct GetTeam: Sendable {

    public enum Result: Equatable, Sendable {
        case own(Team, club: Club)
        case opponent(Team, club: OpponentClub)
    }

    private let clubs: any ClubRepository
    private let teams: any TeamRepository
    private let opponentClubs: any OpponentClubRepository

    public init(
        clubs: any ClubRepository, teams: any TeamRepository,
        opponentClubs: any OpponentClubRepository
    ) {
        self.clubs = clubs
        self.teams = teams
        self.opponentClubs = opponentClubs
    }

    public func execute(_ id: TeamID, actor: ActorContext) async throws -> Result {
        guard let club = try await clubs.current() else {
            throw ApplicationError.tenantNotProvisioned(slug: actor.clubSlug.value)
        }
        guard let team = try await teams.find(id) else {
            throw ApplicationError.teamNotFound(id: "\(id)")
        }
        guard let opponentClubID = team.opponentClubID else {
            return .own(team, club: club)
        }
        // **Por la lista**, como `createSeason` con las temporadas (R2.8): el
        // puerto no tiene una lectura por `id`, y añadirla para esto cambiaría el
        // puerto y sus dobles por una sola llamada.
        guard let rivalClub = try await opponentClubs.list().first(where: { $0.id == opponentClubID })
        else {
            // La FK de `teams.opponent_club_id` lo impide: si pasa, la base está
            // rota, y es un 500, no un «no encontrado».
            throw MissingOpponentClub(team: "\(id)", club: "\(opponentClubID)")
        }
        return .opponent(team, club: rivalClub)
    }

    struct MissingOpponentClub: Error {
        let team: String
        let club: String
    }
}
