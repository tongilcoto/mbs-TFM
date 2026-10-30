public import Domain
import struct Foundation.UUID

/// `GET /v1/matches` (§5.1, R4.8): **partidos, siempre dentro de un ámbito**: una
/// jornada, una competición o un equipo (de local o de visitante), y la
/// temporada para acotar. Paginado, en orden de calendario.
///
/// Cada lado del partido lleva su equipo, con los nombres de su club, y **su
/// fila de la clasificación de esa jornada** (`D-112`), o nada si la jornada no
/// tiene tabla. Todo en pocas lecturas, no una por partido: los partidos del
/// ámbito, las jornadas de sus competiciones, las filas de las jornadas de la
/// página y los equipos.
///
/// **Sin ámbito no se llama**: el adaptador HTTP responde antes con 400
/// `MISSING_SCOPE`.
public struct ListMatches: Sendable {
    private let clubs: any ClubRepository
    private let seasons: any SeasonRepository
    private let competitions: any CompetitionRepository
    private let rounds: any RoundRepository
    private let matches: any MatchRepository
    private let standingRows: any StandingRowRepository
    private let teams: any TeamRepository
    private let opponentClubs: any OpponentClubRepository

    public init(
        clubs: any ClubRepository, seasons: any SeasonRepository, competitions: any CompetitionRepository,
        rounds: any RoundRepository, matches: any MatchRepository, standingRows: any StandingRowRepository,
        teams: any TeamRepository, opponentClubs: any OpponentClubRepository
    ) {
        self.clubs = clubs
        self.seasons = seasons
        self.competitions = competitions
        self.rounds = rounds
        self.matches = matches
        self.standingRows = standingRows
        self.teams = teams
        self.opponentClubs = opponentClubs
    }

    public struct Query: Equatable, Sendable {
        public var roundID: RoundID?
        public var competitionID: CompetitionID?
        public var teamID: TeamID?
        public var seasonID: SeasonID?
        public var status: MatchStatus?
        /// `order=desc`: del más reciente al más antiguo.
        public var newestFirst: Bool
        public var page: Int
        public var perPage: Int

        public init(
            roundID: RoundID? = nil, competitionID: CompetitionID? = nil, teamID: TeamID? = nil,
            seasonID: SeasonID? = nil, status: MatchStatus? = nil, newestFirst: Bool = false,
            page: Int = 1, perPage: Int = 25
        ) {
            self.roundID = roundID
            self.competitionID = competitionID
            self.teamID = teamID
            self.seasonID = seasonID
            self.status = status
            self.newestFirst = newestFirst
            self.page = page
            self.perPage = perPage
        }
    }

    /// Un lado del partido: el equipo con su club, y su fila de esa jornada.
    public struct Side: Equatable, Sendable {
        public let team: LabeledTeam
        public let standing: StandingRow?
    }

    public struct Line: Equatable, Sendable {
        public let match: Match
        public let roundNumber: Int
        public let home: Side
        public let away: Side
    }

    public struct Page: Equatable, Sendable {
        public let lines: [Line]
        /// Los que cumplen el filtro, no solo los de esta página.
        public let total: Int
        public let page: Int
        public let perPage: Int
    }

    public func execute(actor: ActorContext, query: Query) async throws -> Page {
        guard let club = try await clubs.current() else {
            throw ApplicationError.tenantNotProvisioned(slug: actor.clubSlug.value)
        }
        // Cada id del ámbito lo puso quien llama: si no existe, su 404.
        if let id = query.roundID, try await rounds.find(id) == nil {
            throw ApplicationError.roundNotFound(id: "\(id)")
        }
        if let id = query.competitionID, try await competitions.find(id) == nil {
            throw ApplicationError.competitionNotFound(id: "\(id)")
        }
        if let id = query.teamID, try await teams.find(id) == nil {
            throw ApplicationError.teamNotFound(id: "\(id)")
        }
        var seasonCompetitions: Set<CompetitionID>?
        if let id = query.seasonID {
            guard try await seasons.find(id) != nil else { throw ApplicationError.unknownSeason(id: "\(id)") }
            // La temporada se alcanza por la competición: el partido no la lleva (`D-28`).
            seasonCompetitions = Set(try await competitions.list(seasonID: id).map(\.id))
        }

        // Se lee el ámbito más estrecho, y los demás filtros se aplican encima.
        let scoped: [Match]
        if let id = query.roundID {
            scoped = try await matches.list(roundID: id)
        } else if let id = query.competitionID {
            scoped = try await matches.list(competitionID: id)
        } else if let id = query.teamID {
            scoped = try await matches.list(teamID: id)
        } else {
            scoped = []
        }
        let filtered = scoped.filter { match in
            (query.roundID.map { match.roundID == $0 } ?? true)
                && (query.competitionID.map { match.competitionID == $0 } ?? true)
                && (query.teamID.map { match.homeTeamID == $0 || match.awayTeamID == $0 } ?? true)
                && (seasonCompetitions.map { $0.contains(match.competitionID) } ?? true)
                && (query.status.map { match.status == $0 } ?? true)
        }
        let ordered = filtered.sorted(by: Self.calendarOrder)
        let all = query.newestFirst ? Array(ordered.reversed()) : ordered
        let start = (query.page - 1) * query.perPage
        let pageMatches = start < all.count ? Array(all[start..<min(start + query.perPage, all.count)]) : []

        // Lo que lleva cada partido de la página: el número de su jornada, los
        // equipos con su club y la fila de cada lado en esa jornada (`D-112`).
        var numbers: [RoundID: Int] = [:]
        for competition in Set(pageMatches.map(\.competitionID)) {
            for round in try await rounds.list(competitionID: competition) { numbers[round.id] = round.number }
        }
        let rows = try await standingRows.list(roundIDs: Array(Set(pageMatches.map(\.roundID))))
        let standings = Dictionary(rows.map { (RoundTeam(round: $0.roundID, team: $0.teamID), $0) }) { first, _ in first }
        let labels = try await TeamLabels.resolve(
            pageMatches.flatMap { [$0.homeTeamID, $0.awayTeamID] }, club: club, teams: teams,
            opponentClubs: opponentClubs)
        let lines = pageMatches.map { match in
            Line(
                match: match, roundNumber: numbers[match.roundID] ?? 0,
                home: Side(team: labels[match.homeTeamID]!, standing: standings[RoundTeam(round: match.roundID, team: match.homeTeamID)]),
                away: Side(team: labels[match.awayTeamID]!, standing: standings[RoundTeam(round: match.roundID, team: match.awayTeamID)]))
        }
        return Page(lines: lines, total: all.count, page: query.page, perPage: query.perPage)
    }

    private struct RoundTeam: Hashable {
        let round: RoundID
        let team: TeamID
    }

    /// **El orden de calendario** (§5.1): por fecha, y dentro del día por hora,
    /// con las horas sin fijar **al final del día**; el `id` desempata, para que
    /// la paginación sea estable.
    static func calendarOrder(_ lhs: Match, _ rhs: Match) -> Bool {
        func minutes(_ match: Match) -> Int { match.kickoff.time.map { $0.hour * 60 + $0.minute } ?? 24 * 60 }
        if lhs.kickoff.date != rhs.kickoff.date { return lhs.kickoff.date < rhs.kickoff.date }
        if minutes(lhs) != minutes(rhs) { return minutes(lhs) < minutes(rhs) }
        return lhs.id.raw.uuidString < rhs.id.raw.uuidString
    }
}
