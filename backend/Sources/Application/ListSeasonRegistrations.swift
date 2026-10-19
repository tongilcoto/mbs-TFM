public import Domain

/// Caso de uso: los equipos del club en una temporada, cada uno con sus
/// competiciones (`GET /v1/seasons/{seasonId}/registrations`, `D-102`).
///
/// La tabla de inscripciones tiene **una fila por (equipo, competición)**, y la
/// de junio sin competición. La respuesta tiene **un elemento por equipo**, con
/// sus competiciones en una lista, y vacía en junio.
public struct ListSeasonRegistrations: Sendable {
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

    public func execute(actor: ActorContext, seasonID: SeasonID) async throws -> SeasonRegistrations {
        guard let club = try await clubs.current() else {
            throw ApplicationError.tenantNotProvisioned(slug: actor.clubSlug.value)
        }
        // El id lo puso quien llama: si no existe, es un dato suyo, **404**. Una
        // temporada que existe y no tiene inscripciones da la lista vacía.
        guard try await seasons.find(seasonID) != nil else {
            throw ApplicationError.unknownSeason(id: "\(seasonID)")
        }

        let rows = try await registrations.list(seasonID: seasonID)
        let byTeam = Dictionary(grouping: rows, by: \.teamID)
        let teamList = try await teams.list(ids: Array(byTeam.keys))
        let entries = teamList.map { team in
            SeasonRegistration(
                team: team, seasonID: seasonID,
                // La fila de junio no tiene competición y no aporta ninguna: el
                // equipo sale con la lista vacía. Las demás, en el orden en que se
                // inscribieron.
                competitions: (byTeam[team.id] ?? [])
                    .sorted { $0.createdAt < $1.createdAt }
                    .compactMap { row in
                        row.competitionID.map {
                            RegisteredCompetition(competitionID: $0, federationTeamID: row.federationTeamID)
                        }
                    })
        }
        return SeasonRegistrations(club: club, entries: entries.sorted(by: Self.portadaOrder))
    }

    /// El orden de la portada: por categoría, **de menor a mayor edad** (el orden
    /// de `TeamCategory`, no el alfabético), y dentro de ella por letra, con el
    /// equipo sin letra delante.
    static func portadaOrder(_ lhs: SeasonRegistration, _ rhs: SeasonRegistration) -> Bool {
        let ages = TeamCategory.allCases
        let (left, right) = (ages.firstIndex(of: lhs.team.category)!, ages.firstIndex(of: rhs.team.category)!)
        if left != right { return left < right }
        return (lhs.team.letter ?? "") < (rhs.team.letter ?? "")
    }
}

/// Lo que devuelve `ListSeasonRegistrations`. Lleva el club porque la respuesta de
/// un equipo dice de qué club es (`clubName`, `displayName`).
public struct SeasonRegistrations: Equatable, Sendable {
    public let club: Club
    public let entries: [SeasonRegistration]
}

/// **El equipo en una temporada** (`D-102`): el equipo, la temporada y las
/// competiciones en las que está inscrito.
public struct SeasonRegistration: Equatable, Sendable {
    public let team: Team
    public let seasonID: SeasonID
    public let competitions: [RegisteredCompetition]

    public init(team: Team, seasonID: SeasonID, competitions: [RegisteredCompetition]) {
        self.team = team
        self.seasonID = seasonID
        self.competitions = competitions
    }
}

/// Una competición de la inscripción, con el código del equipo en ella (`D-101`).
public struct RegisteredCompetition: Equatable, Sendable {
    public let competitionID: CompetitionID
    public let federationTeamID: String?

    public init(competitionID: CompetitionID, federationTeamID: String?) {
        self.competitionID = competitionID
        self.federationTeamID = federationTeamID
    }
}
