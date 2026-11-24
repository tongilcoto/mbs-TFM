public import Domain
import Foundation

// Las tarjetas del acta (R7.8): las cinco operaciones de `Card`.

/// Las lecturas que comparten las tres escrituras de las tarjetas.
public struct CardRepositories: Sendable {
    let matches: any MatchRepository
    let competitions: any CompetitionRepository
    let seasons: any SeasonRepository
    let teams: any TeamRepository
    let players: any PlayerRepository
    let cards: any CardRepository

    public init(matches: any MatchRepository, competitions: any CompetitionRepository,
                seasons: any SeasonRepository, teams: any TeamRepository, players: any PlayerRepository,
                cards: any CardRepository) {
        self.matches = matches
        self.competitions = competitions
        self.seasons = seasons
        self.teams = teams
        self.players = players
        self.cards = cards
    }

    func context(of id: MatchID, notFound: (MatchID) -> ApplicationError) async throws -> MatchContext {
        try await MatchContext.load(id, matches: matches, competitions: competitions, seasons: seasons,
                                    teams: teams, notFound: notFound)
    }

    /// Las otras tarjetas del jugador en el partido, sin esta.
    func others(of card: Card) async throws -> [Card] {
        try await cards.list(matchID: card.matchID, teamID: nil, playerID: card.playerID).filter { $0.id != card.id }
    }

    /// Lo que mira el alta y la corrección: **una de cada tipo** (§3.5, el 409 mirado
    /// antes de escribir), y la segunda amarilla **sin una amarilla suelta** (`D-45`).
    func requireFits(_ card: Card) async throws {
        let others = try await others(of: card)
        guard !others.contains(where: { $0.type == card.type }) else {
            throw ApplicationError.cardAlreadyRecorded(player: "\(card.playerID)", type: card.type.rawValue)
        }
        try MatchReportRules.requireCard(
            card.type, isSecondYellow: card.isSecondYellow, looseYellow: others.contains { $0.type == .amarilla })
    }
}

/// `GET /v1/cards` (R7.8): las tarjetas de un partido, el historial de un jugador,
/// o **los dos a la vez** (`D-47`).
public struct ListCards: Sendable {
    private let matches: any MatchRepository
    private let teams: any TeamRepository
    private let players: any PlayerRepository
    private let cards: any CardRepository

    public init(matches: any MatchRepository, teams: any TeamRepository, players: any PlayerRepository,
                cards: any CardRepository) {
        self.matches = matches
        self.teams = teams
        self.players = players
        self.cards = cards
    }

    /// **Sin ámbito no se llama**: el adaptador responde antes con 400.
    public func execute(matchID: MatchID?, playerID: PlayerID?, teamID: TeamID?, type: CardType?)
        async throws -> [Card]
    {
        // El 404 **de cada ámbito**.
        if let matchID, try await matches.find(matchID) == nil {
            throw ApplicationError.matchNotFound(id: "\(matchID)")
        }
        if let playerID, try await players.find(playerID) == nil {
            throw ApplicationError.playerNotFound(id: "\(playerID)")
        }
        if let teamID, try await teams.find(teamID) == nil {
            throw ApplicationError.teamNotFound(id: "\(teamID)")
        }
        let rows: [Card]
        if let matchID {
            rows = try await cards.list(matchID: matchID, teamID: teamID, playerID: playerID)
        } else if let playerID {
            // **De lo más reciente a lo más antiguo** (§5.3).
            let own = try await cards.list(playerID: playerID)
            var dates: [MatchID: Date] = [:]
            for card in own { dates[card.matchID] = try await matches.find(card.matchID)?.kickoff.date }
            rows = own.sorted { (dates[$0.matchID] ?? .distantPast) > (dates[$1.matchID] ?? .distantPast) }
        } else {
            rows = []
        }
        return rows.filter { type == nil || $0.type == type }
    }
}

/// `GET /v1/cards/{id}` (R7.8).
public struct GetCard: Sendable {
    private let cards: any CardRepository
    public init(cards: any CardRepository) { self.cards = cards }

    public func execute(_ id: CardID) async throws -> Card {
        guard let card = try await cards.find(id) else { throw ApplicationError.cardNotFound(id: "\(id)") }
        return card
    }
}

/// `POST /v1/cards` (R7.8): apuntar una tarjeta a un jugador del club, con el equipo
/// con el que jugaba (`D-128`). Las del rival no se apuntan (`D-136`).
public struct CreateCard: Sendable {
    private let r: CardRepositories
    private let clock: any Clock
    private let ids: any UUIDProvider

    public init(repositories: CardRepositories, clock: any Clock, ids: any UUIDProvider) {
        self.r = repositories
        self.clock = clock
        self.ids = ids
    }

    public struct Command: Sendable {
        public let playerID: PlayerID
        public let matchID: MatchID
        public let teamID: TeamID
        public let type: CardType
        public let isSecondYellow: Bool
        public let minute: Int?
        public let comment: String?

        public init(playerID: PlayerID, matchID: MatchID, teamID: TeamID, type: CardType,
                    isSecondYellow: Bool = false, minute: Int? = nil, comment: String? = nil) {
            self.playerID = playerID
            self.matchID = matchID
            self.teamID = teamID
            self.type = type
            self.isSecondYellow = isSecondYellow
            self.minute = minute
            self.comment = comment
        }
    }

    public func execute(_ command: Command) async throws -> Card {
        // **422 y no 404**: el partido, el equipo y el jugador llegan en el cuerpo.
        let context = try await r.context(of: command.matchID) { .referenceNotFound(field: "matchId", id: "\($0)") }
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
        try MatchReportRules.requireCanAddEntry(
            started: context.match.kickoff.hasStarted(on: now),
            reportLoaded: try await r.matches.reportCopies(of: [command.matchID])[command.matchID] != nil)

        let card = Card(
            id: CardID(raw: ids.next()), playerID: player.id, matchID: command.matchID, teamID: command.teamID,
            type: command.type, isSecondYellow: command.isSecondYellow,
            minute: try command.minute.map(MatchMinute.init), comment: try EntryComment.make(command.comment),
            createdAt: now, updatedAt: now)
        try await r.requireFits(card)
        try await r.cards.save(card)
        return card
    }
}

/// `PATCH /v1/cards/{id}` (R7.8): corregir el minuto, reclasificar la sanción o
/// escribir el comentario. **Lo que no llega no cambia** (R7.6). En una del acta,
/// solo el comentario (`D-136`, punto 4).
public struct UpdateCard: Sendable {
    private let r: CardRepositories
    private let clock: any Clock

    public init(repositories: CardRepositories, clock: any Clock) {
        self.r = repositories
        self.clock = clock
    }

    public struct Command: Sendable {
        public let type: CardType?
        public let isSecondYellow: Bool?
        public let minute: Int?
        public let comment: String?

        public init(type: CardType? = nil, isSecondYellow: Bool? = nil, minute: Int? = nil, comment: String? = nil) {
            self.type = type
            self.isSecondYellow = isSecondYellow
            self.minute = minute
            self.comment = comment
        }

        public var isEmpty: Bool { type == nil && isSecondYellow == nil && minute == nil && comment == nil }
    }

    public func execute(_ id: CardID, _ command: Command) async throws -> Card {
        guard let card = try await r.cards.find(id) else { throw ApplicationError.cardNotFound(id: "\(id)") }
        let context = try await r.context(of: card.matchID) { .matchNotFound(id: "\($0)") }
        try RosterRules.requireNotArchived(context.season)
        let updated = Card(
            id: card.id, playerID: card.playerID, matchID: card.matchID, teamID: card.teamID,
            type: command.type ?? card.type, isSecondYellow: command.isSecondYellow ?? card.isSecondYellow,
            minute: try command.minute.map(MatchMinute.init) ?? card.minute,
            comment: try command.comment.map(EntryComment.make) ?? card.comment, fromReport: card.fromReport,
            createdAt: card.createdAt, updatedAt: clock.now())
        if card.fromReport { try MatchReportRules.requireReportCardChange(from: card.shape, to: updated.shape) }
        try await r.requireFits(updated)
        try await r.cards.save(updated)
        return updated
    }
}

/// `DELETE /v1/cards/{id}` (R7.8). **Una del acta no se borra** (`D-137`).
public struct DeleteCard: Sendable {
    private let r: CardRepositories
    public init(repositories: CardRepositories) { self.r = repositories }

    public func execute(_ id: CardID) async throws {
        guard let card = try await r.cards.find(id) else { throw ApplicationError.cardNotFound(id: "\(id)") }
        let context = try await r.context(of: card.matchID) { .matchNotFound(id: "\($0)") }
        try RosterRules.requireNotArchived(context.season)
        try MatchReportRules.requireCanDelete(fromReport: card.fromReport)
        try await r.cards.delete(id)
    }
}
