public import Domain
public import struct Foundation.Date

/// Un refuerzo de la plantilla (`D-128`, punto 4): un jugador de otro equipo del club
/// que ha jugado con este en la temporada, **ya contado** en sus actas.
public struct Reinforcement: Equatable, Sendable {
    public let entry: RosterEntry
    /// El equipo de **su** plantilla, no este.
    public let team: LabeledTeam
    public let reportCount: Int
    public let playedCount: Int
    public let convokedWithoutMinutesCount: Int
    public let lastMatch: Match
    public let lastRoundNumber: Int
}

/// `GET /v1/teams/{teamId}/registrations/{seasonId}/reinforcements` (R7.9, la
/// operación 89): **los refuerzos ya contados**, como el resto de las agregaciones
/// (§3.4). Son las convocatorias de este equipo en la temporada de jugadores que no
/// están en su plantilla.
public struct ListTeamReinforcements: Sendable {
    private let clubs: any ClubRepository
    private let seasons: any SeasonRepository
    private let teams: any TeamRepository
    private let opponentClubs: any OpponentClubRepository
    private let registrations: any TeamRegistrationRepository
    private let players: any PlayerRepository
    private let profiles: any PlayerProfileRepository
    private let appearances: any AppearanceRepository
    private let matches: any MatchRepository
    private let rounds: any RoundRepository

    public init(clubs: any ClubRepository, seasons: any SeasonRepository, teams: any TeamRepository,
                opponentClubs: any OpponentClubRepository, registrations: any TeamRegistrationRepository,
                players: any PlayerRepository, profiles: any PlayerProfileRepository,
                appearances: any AppearanceRepository, matches: any MatchRepository, rounds: any RoundRepository) {
        self.clubs = clubs
        self.seasons = seasons
        self.teams = teams
        self.opponentClubs = opponentClubs
        self.registrations = registrations
        self.players = players
        self.profiles = profiles
        self.appearances = appearances
        self.matches = matches
        self.rounds = rounds
    }

    public func execute(actor: ActorContext, teamID: TeamID, seasonID: SeasonID) async throws -> [Reinforcement] {
        guard let club = try await clubs.current() else {
            throw ApplicationError.tenantNotProvisioned(slug: actor.clubSlug.value)
        }
        // Los dos ids los puso quien llama: el 404 de cada uno, como la ficha del
        // equipo (`GetTeamRegistration`).
        guard try await teams.find(teamID) != nil else { throw ApplicationError.teamNotFound(id: "\(teamID)") }
        guard try await seasons.find(seasonID) != nil else { throw ApplicationError.unknownSeason(id: "\(seasonID)") }
        guard !(try await registrations.list(teamID: teamID, seasonID: seasonID)).isEmpty else {
            throw ApplicationError.teamNotRegistered(team: "\(teamID)", season: "\(seasonID)")
        }

        // Las convocatorias de este equipo, por jugador; **refuerzo es el que no está
        // en su plantilla**.
        let rows = try await appearances.list(teamID: teamID, seasonID: seasonID)
        var byPlayer: [PlayerID: [Appearance]] = [:]
        for row in rows { byPlayer[row.playerID, default: []].append(row) }
        var reinforcements: [(Player, [Appearance])] = []
        for (playerID, own) in byPlayer {
            guard let player = try await players.find(playerID), player.teamID != teamID else { continue }
            reinforcements.append((player, own))
        }
        guard !reinforcements.isEmpty else { return [] }

        let entries = Dictionary(uniqueKeysWithValues: try await withTheirProfiles(
            reinforcements.map(\.0), profiles: profiles).map { ($0.player.id, $0) })
        let labels = try await TeamLabels.resolve(
            reinforcements.map(\.0.teamID), club: club, teams: teams, opponentClubs: opponentClubs)
        var matchByID: [MatchID: Match] = [:]
        for id in Set(rows.map(\.matchID)) { matchByID[id] = try await matches.find(id) }

        var result: [Reinforcement] = []
        for (player, own) in reinforcements {
            // Inalcanzables: las FK no dejan una convocatoria sin su partido ni a este
            // sin su jornada, ni una fila sin su perfil o su equipo. Si pasa, la base
            // está rota, y es un 500, como el perfil que falta.
            let played = own.compactMap { row in matchByID[row.matchID].map { (row, $0) } }
            guard let last = played.max(by: { $0.1.kickoff.date < $1.1.kickoff.date })?.1,
                  let round = try await rounds.find(last.roundID),
                  let entry = entries[player.id], let team = labels[player.teamID] else {
                throw ApplicationError.playerProfileMissing(player: "\(player.id)")
            }
            result.append(Reinforcement(
                entry: entry, team: team, reportCount: own.count,
                playedCount: own.filter { $0.status == .jugado }.count,
                convokedWithoutMinutesCount: own.filter { $0.status == .convocadoSinMinutos }.count,
                lastMatch: last, lastRoundNumber: round.number))
        }
        // **Por el último partido**, del más reciente al más antiguo, y el nombre de
        // desempate.
        return result.sorted {
            $0.lastMatch.kickoff.date != $1.lastMatch.kickoff.date
                ? $0.lastMatch.kickoff.date > $1.lastMatch.kickoff.date
                : spanishOrderKey($0.entry.profile.fullName.value) < spanishOrderKey($1.entry.profile.fullName.value)
        }
    }
}

/// El nombre para desempatar, sin tildes ni mayúsculas: un orden estable, no el de
/// la base, que aquí no ordena.
func spanishOrderKey(_ name: String) -> String {
    name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
}
