public import Domain
import Foundation

// La cabecera del acta y la convocatoria (R7.6): `getMatch` y las cinco operaciones
// de `Appearance`. Los goles y las tarjetas, en la R7.7 y la R7.8; la carga del
// acta, en la R7.12.

/// Lo que el acta necesita de su partido para dejar escribir: si es del club, en
/// qué temporada está y si ha empezado. Lo leen todas las escrituras del acta.
struct MatchContext: Sendable {
    let match: Match
    let season: Season
    let ownTeams: Set<TeamID>

    /// El partido **del club** (uno de los dos equipos propios) y su temporada. Un
    /// partido entre dos rivales no tiene acta (`D-130`): no existe para el acta.
    static func load(
        _ id: MatchID, matches: any MatchRepository, competitions: any CompetitionRepository,
        seasons: any SeasonRepository, teams: any TeamRepository, notFound: (MatchID) -> ApplicationError
    ) async throws -> MatchContext {
        guard let match = try await matches.find(id) else { throw notFound(id) }
        var own: Set<TeamID> = []
        for teamID in [match.homeTeamID, match.awayTeamID] {
            if let team = try await teams.find(teamID), team.isOwn { own.insert(teamID) }
        }
        guard !own.isEmpty else { throw notFound(id) }
        // Inalcanzables: las FK no dejan un partido sin su competición ni a esta sin
        // su temporada.
        guard let competition = try await competitions.find(match.competitionID) else {
            throw ApplicationError.competitionNotFound(id: "\(match.competitionID)")
        }
        guard let season = try await seasons.find(competition.seasonID) else {
            throw ApplicationError.seasonNotFound(id: "\(competition.seasonID)")
        }
        return MatchContext(match: match, season: season, ownTeams: own)
    }
}

/// Una convocatoria **como la lee el acta**: la fila, y si ha cambiado respecto al
/// acta cargada (`D-134`, punto 4). Sin acta cargada, nunca ha cambiado.
public struct AppearanceLine: Equatable, Sendable {
    public let appearance: Appearance
    public let changedFromReport: Bool

    public init(appearance: Appearance, changedFromReport: Bool) {
        self.appearance = appearance
        self.changedFromReport = changedFromReport
    }
}

func lines(_ rows: [Appearance], copies: [MatchID: MatchReportCopy]) -> [AppearanceLine] {
    rows.map { AppearanceLine(appearance: $0, changedFromReport: copies[$0.matchID]?.changed($0) ?? false) }
}

// ── La cabecera del acta ──────────────────────────────────────────────────────

/// `GET /v1/matches/{id}` (R7.6): el partido con sus dos lados, como en la lista
/// (`D-112`), la fecha de la carga del acta y **los que el club ha quitado** de la
/// convocatoria que trajo (`D-134`).
public struct GetMatch: Sendable {
    private let list: ListMatches
    private let matches: any MatchRepository
    private let teams: any TeamRepository
    private let appearances: any AppearanceRepository

    public init(
        clubs: any ClubRepository, seasons: any SeasonRepository, competitions: any CompetitionRepository,
        rounds: any RoundRepository, matches: any MatchRepository, standingRows: any StandingRowRepository,
        teams: any TeamRepository, opponentClubs: any OpponentClubRepository,
        appearances: any AppearanceRepository
    ) {
        self.list = ListMatches(clubs: clubs, seasons: seasons, competitions: competitions, rounds: rounds,
                                matches: matches, standingRows: standingRows, teams: teams,
                                opponentClubs: opponentClubs)
        self.matches = matches
        self.teams = teams
        self.appearances = appearances
    }

    public struct Detail: Equatable, Sendable {
        public let line: ListMatches.Line
        public let reportLoadedAt: Date?
        public let removedFromReport: [ReportLineupEntry]
    }

    public func execute(actor: ActorContext, id: MatchID) async throws -> Detail {
        guard let match = try await matches.find(id) else {
            throw ApplicationError.matchNotFound(id: "\(id)")
        }
        // Entre dos rivales, sin acta (`D-130`): el mismo 404 que el que no existe.
        var isOwn = false
        for teamID in [match.homeTeamID, match.awayTeamID] {
            if let team = try await teams.find(teamID), team.isOwn { isOwn = true }
        }
        guard isOwn else { throw ApplicationError.matchNotFound(id: "\(id)") }

        // **Con la misma lectura que la lista**, para que el partido salga igual en
        // los dos sitios: la jornada entera cabe en una página.
        let page = try await list.execute(
            actor: actor, query: ListMatches.Query(roundID: match.roundID, perPage: 100))
        guard let line = page.lines.first(where: { $0.match.id == id }) else {
            throw ApplicationError.matchNotFound(id: "\(id)")
        }
        guard let copy = try await matches.reportCopies(of: [id])[id] else {
            return Detail(line: line, reportLoadedAt: nil, removedFromReport: [])
        }
        let rows = try await appearances.list(matchID: id, teamID: nil)
        return Detail(line: line, reportLoadedAt: copy.loadedAt, removedFromReport: copy.removed(keeping: rows))
    }
}

// ── La convocatoria ───────────────────────────────────────────────────────────

/// `GET /v1/appearances` (R7.6): la convocatoria de un partido o el historial de
/// un jugador, **solo lo apuntado** (`D-134`).
public struct ListAppearances: Sendable {
    private let matches: any MatchRepository
    private let teams: any TeamRepository
    private let players: any PlayerRepository
    private let appearances: any AppearanceRepository

    public init(matches: any MatchRepository, teams: any TeamRepository, players: any PlayerRepository,
                appearances: any AppearanceRepository) {
        self.matches = matches
        self.teams = teams
        self.players = players
        self.appearances = appearances
    }

    /// Las dos puertas, y exactamente una (`D-43`): lo comprueba el adaptador.
    public enum Scope: Sendable {
        case match(MatchID, teamID: TeamID?)
        case player(PlayerID)
    }

    public func execute(_ scope: Scope, status: AppearanceStatus? = nil) async throws -> [AppearanceLine] {
        let rows: [Appearance]
        switch scope {
        case .match(let matchID, let teamID):
            // El 404 **del ámbito**: un partido sin convocatoria es lista vacía.
            guard try await matches.find(matchID) != nil else {
                throw ApplicationError.matchNotFound(id: "\(matchID)")
            }
            if let teamID, try await teams.find(teamID) == nil {
                throw ApplicationError.teamNotFound(id: "\(teamID)")
            }
            rows = try await appearances.list(matchID: matchID, teamID: teamID)
        case .player(let playerID):
            guard try await players.find(playerID) != nil else {
                throw ApplicationError.playerNotFound(id: "\(playerID)")
            }
            // **De lo más reciente a lo más antiguo** (§5.3): el historial se lee así.
            let own = try await appearances.list(playerID: playerID)
            var dates: [MatchID: Date] = [:]
            for row in own { dates[row.matchID] = try await matches.find(row.matchID)?.kickoff.date }
            rows = own.sorted { (dates[$0.matchID] ?? .distantPast) > (dates[$1.matchID] ?? .distantPast) }
        }
        let filtered = rows.filter { status == nil || $0.status == status }
        let copies = try await matches.reportCopies(of: Array(Set(filtered.map(\.matchID))))
        return lines(filtered, copies: copies)
    }
}

/// `GET /v1/appearances/{id}` (R7.6).
public struct GetAppearance: Sendable {
    private let matches: any MatchRepository
    private let appearances: any AppearanceRepository

    public init(matches: any MatchRepository, appearances: any AppearanceRepository) {
        self.matches = matches
        self.appearances = appearances
    }

    public func execute(_ id: AppearanceID) async throws -> AppearanceLine {
        guard let row = try await appearances.find(id) else {
            throw ApplicationError.appearanceNotFound(id: "\(id)")
        }
        return lines([row], copies: try await matches.reportCopies(of: [row.matchID]))[0]
    }
}

/// Las lecturas que comparten las tres escrituras de la convocatoria.
public struct AppearanceRepositories: Sendable {
    let matches: any MatchRepository
    let competitions: any CompetitionRepository
    let seasons: any SeasonRepository
    let teams: any TeamRepository
    let players: any PlayerRepository
    let appearances: any AppearanceRepository

    public init(matches: any MatchRepository, competitions: any CompetitionRepository,
                seasons: any SeasonRepository, teams: any TeamRepository, players: any PlayerRepository,
                appearances: any AppearanceRepository) {
        self.matches = matches
        self.competitions = competitions
        self.seasons = seasons
        self.teams = teams
        self.players = players
        self.appearances = appearances
    }

    func context(of id: MatchID, notFound: (MatchID) -> ApplicationError) async throws -> MatchContext {
        try await MatchContext.load(id, matches: matches, competitions: competitions, seasons: seasons,
                                    teams: teams, notFound: notFound)
    }

    func line(_ row: Appearance) async throws -> AppearanceLine {
        lines([row], copies: try await matches.reportCopies(of: [row.matchID]))[0]
    }
}

/// `POST /v1/appearances` (R7.6): apuntar a un jugador en la convocatoria de un
/// partido, con el equipo con el que juega (`D-128`) y un estado (`D-134`).
public struct CreateAppearance: Sendable {
    private let r: AppearanceRepositories
    private let clock: any Clock
    private let ids: any UUIDProvider

    public init(repositories: AppearanceRepositories, clock: any Clock, ids: any UUIDProvider) {
        self.r = repositories
        self.clock = clock
        self.ids = ids
    }

    public struct Command: Sendable {
        public let playerID: PlayerID
        public let matchID: MatchID
        public let teamID: TeamID
        public let status: AppearanceStatus
        public let shirtNumber: Int?
        public let minutes: Int?

        public init(playerID: PlayerID, matchID: MatchID, teamID: TeamID, status: AppearanceStatus,
                    shirtNumber: Int? = nil, minutes: Int? = nil) {
            self.playerID = playerID
            self.matchID = matchID
            self.teamID = teamID
            self.status = status
            self.shirtNumber = shirtNumber
            self.minutes = minutes
        }
    }

    public func execute(_ command: Command) async throws -> AppearanceLine {
        // **422 y no 404**: el partido, el equipo y el jugador llegan en el cuerpo.
        let context = try await r.context(of: command.matchID) {
            .referenceNotFound(field: "matchId", id: "\($0)")
        }
        guard try await r.teams.find(command.teamID) != nil else {
            throw ApplicationError.referenceNotFound(field: "teamId", id: "\(command.teamID)")
        }
        guard let player = try await r.players.find(command.playerID) else {
            throw ApplicationError.referenceNotFound(field: "playerId", id: "\(command.playerID)")
        }
        try RosterRules.requireNotArchived(context.season)
        try MatchReportRules.requireTeam(
            command.teamID, isOwn: context.ownTeams.contains(command.teamID),
            playsIn: (context.match.homeTeamID, context.match.awayTeamID))
        try MatchReportRules.requirePlayer(player.id, inSeason: player.seasonID, matchSeason: context.season.id)

        let now = clock.now()
        try MatchReportRules.requireCanRecord(command.status, started: context.match.kickoff.hasStarted(on: now))
        let shirt = try command.shirtNumber.map(ShirtNumber.init)
        let minutes = try command.minutes.map(MinutesPlayed.init)
        try MatchReportRules.requireMinutes(minutes, for: command.status)

        // **Mirado antes de escribir**, como el dorsal (R6.6): la base lo sostiene
        // con su índice, y este es el 409 con su código.
        guard try await r.appearances.find(playerID: player.id, matchID: command.matchID) == nil else {
            throw ApplicationError.playerAlreadyConvoked(player: "\(player.id)", match: "\(command.matchID)")
        }
        let appearance = Appearance(
            id: AppearanceID(raw: ids.next()), playerID: player.id, matchID: command.matchID,
            teamID: command.teamID, status: command.status, shirtNumber: shirt, minutes: minutes,
            createdAt: now, updatedAt: now)
        try await r.appearances.save(appearance)
        return try await r.line(appearance)
    }
}

/// `PATCH /v1/appearances/{id}` (R7.6): cambiar el estado, el dorsal o los minutos.
///
/// **Un campo que no llega no cambia**, y un `null` tampoco: el generador no los
/// distingue (`D-65`). Los minutos se quitan **al dejar «Jugado»** (R7.3, P4), y
/// el dorsal lo pone la carga del acta (`D-129`); la web no los vacía.
public struct UpdateAppearance: Sendable {
    private let r: AppearanceRepositories
    private let clock: any Clock

    public init(repositories: AppearanceRepositories, clock: any Clock) {
        self.r = repositories
        self.clock = clock
    }

    public struct Command: Sendable {
        public let status: AppearanceStatus?
        public let shirtNumber: Int?
        public let minutes: Int?

        public init(status: AppearanceStatus? = nil, shirtNumber: Int? = nil, minutes: Int? = nil) {
            self.status = status
            self.shirtNumber = shirtNumber
            self.minutes = minutes
        }

        public var isEmpty: Bool { status == nil && shirtNumber == nil && minutes == nil }
    }

    public func execute(_ id: AppearanceID, _ command: Command) async throws -> AppearanceLine {
        guard let row = try await r.appearances.find(id) else {
            throw ApplicationError.appearanceNotFound(id: "\(id)")
        }
        let context = try await r.context(of: row.matchID) { .matchNotFound(id: "\($0)") }
        try RosterRules.requireNotArchived(context.season)

        let now = clock.now()
        let status = command.status ?? row.status
        try MatchReportRules.requireChange(
            from: row.status, to: status, started: context.match.kickoff.hasStarted(on: now))
        // Unos minutos que llegan con un estado que no es «Jugado» no se tiran
        // callando: son un error de quien llama (`D-42`).
        let sentMinutes = try command.minutes.map(MinutesPlayed.init)
        try MatchReportRules.requireMinutes(sentMinutes, for: status)
        let minutes = MatchReportRules.minutes(sentMinutes ?? row.minutes, after: status)
        let updated = Appearance(
            id: row.id, playerID: row.playerID, matchID: row.matchID, teamID: row.teamID, status: status,
            shirtNumber: try command.shirtNumber.map(ShirtNumber.init) ?? row.shirtNumber, minutes: minutes,
            createdAt: row.createdAt, updatedAt: now)
        try await r.appearances.save(updated)
        return try await r.line(updated)
    }
}

/// `DELETE /v1/appearances/{id}` (R7.6): **«no convocado»** (`D-134`). Borrado lógico.
public struct DeleteAppearance: Sendable {
    private let r: AppearanceRepositories

    public init(repositories: AppearanceRepositories) { self.r = repositories }

    public func execute(_ id: AppearanceID) async throws {
        guard let row = try await r.appearances.find(id) else {
            throw ApplicationError.appearanceNotFound(id: "\(id)")
        }
        let context = try await r.context(of: row.matchID) { .matchNotFound(id: "\($0)") }
        try RosterRules.requireNotArchived(context.season)
        try await r.appearances.delete(id)
    }
}
