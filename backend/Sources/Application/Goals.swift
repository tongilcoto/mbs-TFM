public import Domain
import Foundation

// Los goles del acta (R7.7): las cinco operaciones de `Goal`.

/// Las lecturas que comparten las tres escrituras de los goles.
public struct GoalRepositories: Sendable {
    let matches: any MatchRepository
    let competitions: any CompetitionRepository
    let seasons: any SeasonRepository
    let teams: any TeamRepository
    let players: any PlayerRepository
    let goals: any GoalRepository

    public init(matches: any MatchRepository, competitions: any CompetitionRepository,
                seasons: any SeasonRepository, teams: any TeamRepository, players: any PlayerRepository,
                goals: any GoalRepository) {
        self.matches = matches
        self.competitions = competitions
        self.seasons = seasons
        self.teams = teams
        self.players = players
        self.goals = goals
    }

    func context(of id: MatchID, notFound: (MatchID) -> ApplicationError) async throws -> MatchContext {
        try await MatchContext.load(id, matches: matches, competitions: competitions, seasons: seasons,
                                    teams: teams, notFound: notFound)
    }

    /// El goleador y el asistente de un gol (`D-52`, `D-128`): **del club en la
    /// temporada del partido**, y **del lado propio**: el goleador, del equipo que
    /// le toca según la jugada; el asistente, del que marca.
    func requirePeople(of goal: Goal, in context: MatchContext) async throws {
        if let scorer = goal.scorer {
            try await requirePlayer(scorer, field: "scorerPlayerId", in: context)
            guard context.ownTeams.contains(goal.scorerTeamID) else {
                throw DomainError.invalidValue(
                    field: "scorerPlayerId", reason: "el goleador de ese lado es del rival: va sin goleador")
            }
        }
        if let assist = goal.assist {
            try await requirePlayer(assist, field: "assistPlayerId", in: context)
            guard context.ownTeams.contains(goal.scoringTeamID) else {
                throw DomainError.invalidValue(
                    field: "assistPlayerId", reason: "el asistente de un gol del rival es del rival")
            }
        }
    }

    private func requirePlayer(_ id: PlayerID, field: String, in context: MatchContext) async throws {
        guard let player = try await players.find(id) else {
            throw ApplicationError.referenceNotFound(field: field, id: "\(id)")
        }
        try MatchReportRules.requirePlayer(id, inSeason: player.seasonID, matchSeason: context.season.id)
    }
}

/// Lo que trae el cuerpo de un gol, en el alta y en la corrección.
public struct GoalFields: Sendable {
    public var scorer: PlayerID?
    public var assist: PlayerID?
    public var assisted: Bool?
    public var minute: Int?
    public var zone: GoalZone?
    public var attackSide: GoalSide?
    public var shotSide: GoalSide?
    public var bodyPart: GoalBodyPart?
    public var playType: GoalPlayType?
    public var comment: String?

    public init(scorer: PlayerID? = nil, assist: PlayerID? = nil, assisted: Bool? = nil, minute: Int? = nil,
                zone: GoalZone? = nil, attackSide: GoalSide? = nil, shotSide: GoalSide? = nil,
                bodyPart: GoalBodyPart? = nil, playType: GoalPlayType? = nil, comment: String? = nil) {
        self.scorer = scorer
        self.assist = assist
        self.assisted = assisted
        self.minute = minute
        self.zone = zone
        self.attackSide = attackSide
        self.shotSide = shotSide
        self.bodyPart = bodyPart
        self.playType = playType
        self.comment = comment
    }

    public var isEmpty: Bool {
        scorer == nil && assist == nil && assisted == nil && minute == nil && zone == nil && attackSide == nil
            && shotSide == nil && bodyPart == nil && playType == nil && comment == nil
    }

    /// El gol con lo que trae el cuerpo encima de lo que tenía: **lo que no llega
    /// no cambia** (R7.6, `D-65`).
    func applied(to goal: Goal, updatedAt: Date) throws -> Goal {
        Goal(
            id: goal.id, matchID: goal.matchID, scoringTeamID: goal.scoringTeamID,
            concedingTeamID: goal.concedingTeamID, scorer: scorer ?? goal.scorer, assist: assist ?? goal.assist,
            assisted: assisted ?? goal.assisted, minute: try minute.map(MatchMinute.init) ?? goal.minute,
            zone: zone ?? goal.zone, attackSide: attackSide ?? goal.attackSide, shotSide: shotSide ?? goal.shotSide,
            bodyPart: bodyPart ?? goal.bodyPart, playType: playType ?? goal.playType,
            comment: try comment.map(EntryComment.make) ?? goal.comment, fromReport: goal.fromReport,
            createdAt: goal.createdAt, updatedAt: updatedAt)
    }
}

/// `GET /v1/goals` (R7.7): una página de goles, con las cuatro puertas y sus filtros.
public struct ListGoals: Sendable {
    private let matches: any MatchRepository
    private let teams: any TeamRepository
    private let players: any PlayerRepository
    private let seasons: any SeasonRepository
    private let goals: any GoalRepository

    public init(matches: any MatchRepository, teams: any TeamRepository, players: any PlayerRepository,
                seasons: any SeasonRepository, goals: any GoalRepository) {
        self.matches = matches
        self.teams = teams
        self.players = players
        self.seasons = seasons
        self.goals = goals
    }

    public struct Page: Equatable, Sendable {
        public let goals: [Goal]
        public let total: Int
        public let page: Int
        public let perPage: Int
    }

    /// **Sin ámbito no se llama**: el adaptador responde antes con 400.
    public func execute(_ filter: GoalFilter, page: Int, perPage: Int) async throws -> Page {
        // El 404 **de cada ámbito**: lo que existe y no tiene goles es página vacía.
        if let id = filter.matchID, try await matches.find(id) == nil {
            throw ApplicationError.matchNotFound(id: "\(id)")
        }
        for id in [filter.scoringTeamID, filter.concedingTeamID].compactMap({ $0 }) {
            guard try await teams.find(id) != nil else { throw ApplicationError.teamNotFound(id: "\(id)") }
        }
        for id in [filter.scorer, filter.assist].compactMap({ $0 }) {
            guard try await players.find(id) != nil else { throw ApplicationError.playerNotFound(id: "\(id)") }
        }
        if let id = filter.seasonID, try await seasons.find(id) == nil {
            throw ApplicationError.unknownSeason(id: "\(id)")
        }
        let (rows, total) = try await goals.list(filter, page: page, perPage: perPage)
        return Page(goals: rows, total: total, page: page, perPage: perPage)
    }
}

/// `GET /v1/goals/{id}` (R7.7).
public struct GetGoal: Sendable {
    private let goals: any GoalRepository
    public init(goals: any GoalRepository) { self.goals = goals }

    public func execute(_ id: GoalID) async throws -> Goal {
        guard let goal = try await goals.find(id) else { throw ApplicationError.goalNotFound(id: "\(id)") }
        return goal
    }
}

/// `POST /v1/goals` (R7.7): apuntar un gol. **Se manda quién marca; el servidor
/// deriva quién encaja** (`D-54`).
public struct CreateGoal: Sendable {
    private let r: GoalRepositories
    private let clock: any Clock
    private let ids: any UUIDProvider

    public init(repositories: GoalRepositories, clock: any Clock, ids: any UUIDProvider) {
        self.r = repositories
        self.clock = clock
        self.ids = ids
    }

    public func execute(matchID: MatchID, scoringTeamID: TeamID, _ fields: GoalFields) async throws -> Goal {
        // **422 y no 404**: el partido y el equipo llegan en el cuerpo. Un partido
        // entre dos rivales no tiene acta (`D-130`).
        let context = try await r.context(of: matchID) { .referenceNotFound(field: "matchId", id: "\($0)") }
        let match = context.match
        guard scoringTeamID == match.homeTeamID || scoringTeamID == match.awayTeamID else {
            throw DomainError.teamNotInMatch(team: scoringTeamID.description)
        }
        try RosterRules.requireNotArchived(context.season)
        let now = clock.now()
        try MatchReportRules.requireCanAddEntry(
            started: match.kickoff.hasStarted(on: now),
            reportLoaded: try await r.matches.reportCopies(of: [matchID])[matchID] != nil)

        let blank = Goal(
            id: GoalID(raw: ids.next()), matchID: matchID, scoringTeamID: scoringTeamID,
            concedingTeamID: scoringTeamID == match.homeTeamID ? match.awayTeamID : match.homeTeamID,
            createdAt: now, updatedAt: now)
        let goal = try fields.applied(to: blank, updatedAt: now)
        try MatchReportRules.requireShape(goal.shape)
        try await r.requirePeople(of: goal, in: context)
        try await r.goals.save(goal)
        return goal
    }
}

/// `PATCH /v1/goals/{id}` (R7.7): corregir un gol o completar su desglose. **Lo que
/// no llega no cambia**, y un `null` tampoco (R7.6). En uno del acta, lo de la
/// federación queda fijo (`D-135`, punto 6).
public struct UpdateGoal: Sendable {
    private let r: GoalRepositories
    private let clock: any Clock

    public init(repositories: GoalRepositories, clock: any Clock) {
        self.r = repositories
        self.clock = clock
    }

    public func execute(_ id: GoalID, _ fields: GoalFields) async throws -> Goal {
        guard let goal = try await r.goals.find(id) else { throw ApplicationError.goalNotFound(id: "\(id)") }
        let context = try await r.context(of: goal.matchID) { .matchNotFound(id: "\($0)") }
        try RosterRules.requireNotArchived(context.season)
        let updated = try fields.applied(to: goal, updatedAt: clock.now())
        if goal.fromReport { try MatchReportRules.requireReportGoalChange(from: goal.shape, to: updated.shape) }
        try MatchReportRules.requireShape(updated.shape)
        try await r.requirePeople(of: updated, in: context)
        try await r.goals.save(updated)
        return updated
    }
}

/// `DELETE /v1/goals/{id}` (R7.7). **Uno del acta no se borra** (`D-137`).
public struct DeleteGoal: Sendable {
    private let r: GoalRepositories
    public init(repositories: GoalRepositories) { self.r = repositories }

    public func execute(_ id: GoalID) async throws {
        guard let goal = try await r.goals.find(id) else { throw ApplicationError.goalNotFound(id: "\(id)") }
        let context = try await r.context(of: goal.matchID) { .matchNotFound(id: "\($0)") }
        try RosterRules.requireNotArchived(context.season)
        try MatchReportRules.requireCanDelete(fromReport: goal.fromReport)
        try await r.goals.delete(id)
    }
}
