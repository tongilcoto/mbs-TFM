public import Domain
import Foundation

// Las cinco operaciones de datos de la plantilla (R6.6). Las tres de la foto y
// la búsqueda de perfiles llegan en la R6.7 y la R6.9; la sincronización, en la
// R6.14.

/// El año en curso, **en Madrid**: es el del club, y un 31 de diciembre a las
/// once de la noche en UTC ya es el año siguiente allí.
func currentYear(_ clock: any Clock) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
    return calendar.component(.year, from: clock.now())
}

/// Las filas con su perfil. Un perfil que falta es la base rota: la FK es
/// `RESTRICT` y no lo deja borrar con filas.
func withTheirProfiles(_ players: [Player], profiles: any PlayerProfileRepository)
    async throws -> [RosterEntry]
{
    guard !players.isEmpty else { return [] }
    let byID = Dictionary(
        uniqueKeysWithValues: try await profiles.list(ids: players.map(\.profileID)).map { ($0.id, $0) })
    return try players.map { player in
        guard let profile = byID[player.profileID] else {
            throw ApplicationError.playerProfileMissing(player: "\(player.id)")
        }
        return RosterEntry(player: player, profile: profile)
    }
}

// ── La plantilla ──────────────────────────────────────────────────────────────

/// La plantilla de un equipo en una temporada (`GET /players`).
public struct ListPlayers: Sendable {
    private let teams: any TeamRepository
    private let seasons: any SeasonRepository
    private let players: any PlayerRepository
    private let profiles: any PlayerProfileRepository

    public init(teams: any TeamRepository, seasons: any SeasonRepository,
                players: any PlayerRepository, profiles: any PlayerProfileRepository) {
        self.teams = teams
        self.seasons = seasons
        self.players = players
        self.profiles = profiles
    }

    public func execute(teamID: TeamID, seasonID: SeasonID, position: PlayerPosition? = nil)
        async throws -> [RosterEntry]
    {
        // El 404 **del ámbito**: si el equipo o la temporada no existen, no hay
        // plantilla que pedir. Un equipo propio sin jugadores es lista vacía.
        guard let team = try await teams.find(teamID) else {
            throw ApplicationError.teamNotFound(id: "\(teamID)")
        }
        guard try await seasons.find(seasonID) != nil else {
            throw ApplicationError.unknownSeason(id: "\(seasonID)")
        }
        // Un rival no tiene plantilla (§3.7): lista vacía, no error.
        guard team.isOwn else { return [] }

        let rows = try await players.list(teamID: teamID, seasonID: seasonID)
            .filter { position == nil || $0.position == position }
        return Self.ordered(try await withTheirProfiles(rows, profiles: profiles))
    }

    /// **Por dorsal, y después los que no tienen, por nombre** (`D-118`). El nombre
    /// desempata también entre los que tienen dorsal, aunque no puedan repetirlo:
    /// así el orden es total y no depende de cómo lo devuelva la base.
    static func ordered(_ entries: [RosterEntry]) -> [RosterEntry] {
        entries.sorted { left, right in
            switch (left.player.shirtNumber?.value, right.player.shirtNumber?.value) {
            case let (l?, r?) where l != r: return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            default: return left.profile.fullName.value < right.profile.fullName.value
            }
        }
    }
}

/// Un jugador en una temporada (`GET /players/{id}`).
public struct GetPlayer: Sendable {
    private let players: any PlayerRepository
    private let profiles: any PlayerProfileRepository

    public init(players: any PlayerRepository, profiles: any PlayerProfileRepository) {
        self.players = players
        self.profiles = profiles
    }

    public func execute(_ id: PlayerID) async throws -> RosterEntry {
        guard let player = try await players.find(id) else {
            throw ApplicationError.playerNotFound(id: "\(id)")
        }
        return try await withTheirProfiles([player], profiles: profiles)[0]
    }
}

// ── El alta ───────────────────────────────────────────────────────────────────

/// El alta en la plantilla (`POST /players`), con un perfil que ya existe o con
/// un jugador nuevo (`D-120`).
public struct CreatePlayer: Sendable {
    private let teams: any TeamRepository
    private let seasons: any SeasonRepository
    private let players: any PlayerRepository
    private let profiles: any PlayerProfileRepository
    private let clock: any Clock
    private let ids: any UUIDProvider

    public init(teams: any TeamRepository, seasons: any SeasonRepository,
                players: any PlayerRepository, profiles: any PlayerProfileRepository,
                clock: any Clock, ids: any UUIDProvider) {
        self.teams = teams
        self.seasons = seasons
        self.players = players
        self.profiles = profiles
        self.clock = clock
        self.ids = ids
    }

    /// Las dos formas del alta, y exactamente una (`D-120`).
    public enum Who: Sendable {
        case profile(PlayerProfileID)
        case newPlayer(fullName: String, birthYear: Int)
    }

    public struct Command: Sendable {
        public let teamID: TeamID
        public let seasonID: SeasonID
        public let who: Who
        public let shirtNumber: Int?
        public let position: PlayerPosition?

        public init(teamID: TeamID, seasonID: SeasonID, who: Who,
                    shirtNumber: Int? = nil, position: PlayerPosition? = nil) {
            self.teamID = teamID
            self.seasonID = seasonID
            self.who = who
            self.shirtNumber = shirtNumber
            self.position = position
        }
    }

    public func execute(_ command: Command) async throws -> RosterEntry {
        // **422 y no 404**: el equipo, la temporada y el perfil llegan en el
        // cuerpo, y `/players` sí existe (§5.1).
        guard let team = try await teams.find(command.teamID) else {
            throw ApplicationError.referenceNotFound(field: "teamId", id: "\(command.teamID)")
        }
        guard let season = try await seasons.find(command.seasonID) else {
            throw ApplicationError.referenceNotFound(field: "seasonId", id: "\(command.seasonID)")
        }
        try RosterRules.requireCanAdd(to: team, in: season)

        let shirt = try command.shirtNumber.map(ShirtNumber.init)
        let now = clock.now()

        let profile: PlayerProfile
        var isNewProfile = false
        switch command.who {
        case .profile(let id):
            guard let existing = try await profiles.find(id) else {
                throw ApplicationError.referenceNotFound(field: "profileId", id: "\(id)")
            }
            // **Un jugador, una plantilla por temporada** (`D-121`). Se mira antes
            // de escribir, no esperando al índice: así sale con su código.
            guard try await players.list(profileID: id, seasonID: season.id).isEmpty else {
                throw ApplicationError.playerAlreadyInRoster(profile: "\(id)", season: "\(season.id)")
            }
            profile = existing
        case .newPlayer(let fullName, let birthYear):
            profile = PlayerProfile(
                id: PlayerProfileID(raw: ids.next()), fullName: try PlayerName(fullName),
                birthYear: try BirthYear(birthYear, notAfter: currentYear(clock)),
                createdAt: now, updatedAt: now)
            isNewProfile = true
        }

        try await requireShirtFree(shirt, team: team.id, season: season.id, except: nil,
                                   players: players)

        // **La fila empieza con la foto del perfil** (`D-122`, R6.9): el alta no lleva
        // foto, que se sube aparte (`D-35`), y copiar al perfil la de una fila vacía
        // le borraba la suya. Como la sincronización (`D-120`). Un jugador nuevo no tiene.
        let player = Player(
            id: PlayerID(raw: ids.next()), profileID: profile.id, teamID: team.id,
            seasonID: season.id, shirtNumber: shirt, position: command.position,
            photoKey: profile.lastPhotoKey, createdAt: now, updatedAt: now)
        if isNewProfile { try await profiles.save(profile) }
        try await players.save(player)
        // Lo que guarda la fila, al perfil, como ayuda para la próxima alta (`D-122`).
        try await profiles.save(profile.remembering(player))

        // Se relee para devolver las marcas de tiempo que puso la base.
        return try await GetPlayer(players: players, profiles: profiles).execute(player.id)
    }
}

/// **El dorsal, sin repetir entre los no borrados** (`D-118`). Se mira antes de
/// escribir para que salga con su código; el índice de la base es la red.
func requireShirtFree(
    _ shirt: ShirtNumber?, team: TeamID, season: SeasonID, except: PlayerID?,
    players: any PlayerRepository
) async throws {
    guard let shirt else { return }
    let taken = try await players.list(teamID: team, seasonID: season)
        .contains { $0.shirtNumber == shirt && $0.id != except }
    if taken { throw ApplicationError.shirtNumberTaken(number: shirt.value) }
}

// ── Corregir ──────────────────────────────────────────────────────────────────

/// Corregir un jugador con su ficha entera (`PUT /players/{id}`, R6.6).
public struct UpdatePlayer: Sendable {
    private let seasons: any SeasonRepository
    private let players: any PlayerRepository
    private let profiles: any PlayerProfileRepository
    private let clock: any Clock

    public init(seasons: any SeasonRepository, players: any PlayerRepository,
                profiles: any PlayerProfileRepository, clock: any Clock) {
        self.seasons = seasons
        self.players = players
        self.profiles = profiles
        self.clock = clock
    }

    /// **La ficha entera**: lo que no llega, o llega vacío, queda vacío.
    public struct Command: Sendable {
        public let fullName: String
        public let birthYear: Int?
        public let shirtNumber: Int?
        public let position: PlayerPosition?

        public init(fullName: String, birthYear: Int?, shirtNumber: Int?,
                    position: PlayerPosition?) {
            self.fullName = fullName
            self.birthYear = birthYear
            self.shirtNumber = shirtNumber
            self.position = position
        }
    }

    public func execute(_ id: PlayerID, _ command: Command) async throws -> RosterEntry {
        let entry = try await GetPlayer(players: players, profiles: profiles).execute(id)
        let (player, profile) = (entry.player, entry.profile)
        try await requireEditable(player.seasonID, seasons: seasons)

        let name = try PlayerName(command.fullName)
        let year: BirthYear?
        switch command.birthYear {
        case .some(let value):
            year = try BirthYear(value, notAfter: currentYear(clock))
        case .none where profile.birthYear != nil:
            // Se puede poner o cambiar, no quitar: un perfil sin año solo lo deja
            // la sincronización (`D-120`).
            throw DomainError.invalidValue(field: "birthYear", reason: "no se puede quitar")
        case .none:
            year = nil
        }
        let shirt = try command.shirtNumber.map(ShirtNumber.init)
        try await requireShirtFree(shirt, team: player.teamID, season: player.seasonID,
                                   except: player.id, players: players)

        let corrected = Player(
            id: player.id, profileID: player.profileID, teamID: player.teamID,
            seasonID: player.seasonID, shirtNumber: shirt, position: command.position,
            photoKey: player.photoKey, createdAt: player.createdAt, updatedAt: player.updatedAt)
        try await players.save(corrected)
        // El nombre y el año, del perfil: cambian en todas sus temporadas (`D-119`).
        // Y lo de la fila, al perfil, lo vacío también (`D-122`).
        try await profiles.save(PlayerProfile(
            id: profile.id, fullName: name, birthYear: year,
            createdAt: profile.createdAt, updatedAt: profile.updatedAt
        ).remembering(corrected))

        return try await GetPlayer(players: players, profiles: profiles).execute(id)
    }
}

/// La temporada de una fila, para mirar si está archivada. Que no esté es la base
/// rota: la FK la protege.
func requireEditable(_ seasonID: SeasonID, seasons: any SeasonRepository) async throws {
    guard let season = try await seasons.find(seasonID) else {
        throw ApplicationError.seasonNotFound(id: "\(seasonID)")
    }
    try RosterRules.requireEditable(in: season)
}

// ── La baja ───────────────────────────────────────────────────────────────────

/// Dar de baja (`DELETE /players/{id}`): borrado lógico (`D-36`). **No toca el
/// perfil** (`D-119`), y libera el dorsal.
public struct DeletePlayer: Sendable {
    private let seasons: any SeasonRepository
    private let players: any PlayerRepository

    public init(seasons: any SeasonRepository, players: any PlayerRepository) {
        self.seasons = seasons
        self.players = players
    }

    public func execute(_ id: PlayerID) async throws {
        guard let player = try await players.find(id) else {
            throw ApplicationError.playerNotFound(id: "\(id)")
        }
        try await requireEditable(player.seasonID, seasons: seasons)
        try await players.delete(id)
    }
}

// ── El buscador del alta (R6.7) ───────────────────────────────────────────────

/// Los perfiles del club que encajan con lo escrito, para el alta en una
/// plantilla (`GET /player-profiles`, `D-120`).
public struct SearchPlayerProfiles: Sendable {
    private let clubs: any ClubRepository
    private let teams: any TeamRepository
    private let opponentClubs: any OpponentClubRepository
    private let seasons: any SeasonRepository
    private let players: any PlayerRepository
    private let profiles: any PlayerProfileRepository

    public init(clubs: any ClubRepository, teams: any TeamRepository,
                opponentClubs: any OpponentClubRepository, seasons: any SeasonRepository,
                players: any PlayerRepository, profiles: any PlayerProfileRepository) {
        self.clubs = clubs
        self.teams = teams
        self.opponentClubs = opponentClubs
        self.seasons = seasons
        self.players = players
        self.profiles = profiles
    }

    /// Hasta diez (`D-120`): los que caben en la lista del buscador.
    public static let limit = 10

    /// Una plantilla en la que estuvo: su equipo, con sus rótulos, y la temporada.
    public struct Roster: Equatable, Sendable {
        public let team: LabeledTeam
        public let season: Season
    }

    public struct Match: Equatable, Sendable {
        public let profile: PlayerProfile
        /// La fila no borrada más reciente, o `nil` si no tiene ninguna.
        public let lastRoster: Roster?
        /// El equipo en el que ya está esta temporada, si es otro (`D-121`).
        public let otherTeamThisSeason: LabeledTeam?
    }

    public func execute(_ search: PlayerSearch, teamID: TeamID, seasonID: SeasonID,
                        actor: ActorContext) async throws -> [Match] {
        // El 404 del ámbito, como `listPlayers`.
        guard try await teams.find(teamID) != nil else {
            throw ApplicationError.teamNotFound(id: "\(teamID)")
        }
        guard try await seasons.find(seasonID) != nil else {
            throw ApplicationError.unknownSeason(id: "\(seasonID)")
        }
        let found = try await profiles.search(
            search, excludingRosterOf: teamID, seasonID: seasonID, limit: Self.limit)
        guard !found.isEmpty else { return [] }

        guard let club = try await clubs.current() else {
            throw ApplicationError.tenantNotProvisioned(slug: actor.clubSlug.value)
        }
        let rows = try await players.list(profileIDs: found.map(\.id))
        let seasonsByID = Dictionary(
            uniqueKeysWithValues: try await seasons.list(includingArchived: true).map { ($0.id, $0) })
        let labels = try await TeamLabels.resolve(
            rows.map(\.teamID), club: club, teams: teams, opponentClubs: opponentClubs)

        return found.map { profile in
            let theirs = rows.filter { $0.profileID == profile.id }
            // **La más reciente, por la temporada**: no por la fecha de alta, que
            // puede ser de una temporada pasada escrita tarde.
            let last = theirs
                .compactMap { row in seasonsByID[row.seasonID].map { (row, $0) } }
                .max { $0.1.label.startYear < $1.1.label.startYear }
            let other = theirs.first { $0.seasonID == seasonID && $0.teamID != teamID }
            return Match(
                profile: profile,
                lastRoster: last.flatMap { row, season in
                    labels[row.teamID].map { Roster(team: $0, season: season) }
                },
                otherTeamThisSeason: other.flatMap { labels[$0.teamID] })
        }
    }
}
