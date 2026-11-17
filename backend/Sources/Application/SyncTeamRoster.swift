public import Domain
public import Foundation

/// **Sincronizar la plantilla con la federación** (`D-120`, R6.14):
/// `POST /teams/{teamId}/registrations/{seasonId}/roster-sync`.
///
/// Lee la plantilla que publica la federación del equipo y **solo añade**: no
/// corrige ni da de baja a nadie, y se puede pulsar siempre. Cada jugador publicado,
/// según cómo está en el club:
///
/// - **No lo tiene**: perfil nuevo, sin año (la federación no lo da), y su fila.
/// - **Casa con un perfil** por «el mismo nombre» (`PlayerName.sameNameKey`): solo la
///   fila, con el dorsal, la demarcación y la foto que guarda el perfil (`D-122`); el
///   dorsal, solo si está libre. Salvo que ya esté en la plantilla, que el club lo
///   diera de baja de ella, o que esté en otro equipo de la temporada (`D-121`).
/// - **Casa con varios**: perfil nuevo, y el resumen lo nombra para revisarlo.
/// - **Su nombre no vale**: no se añade, y el resumen lo da como lo escribe la
///   federación.
///
/// Después, cada fila de la plantilla queda federada si la federación la publica y
/// no federada si no, y la inscripción guarda la fecha. **Una ficha sin jugadores se
/// acepta como verdad** (decisión 5 de R6.14): todos quedan no federados.
///
/// # En tres tiempos, y la federación fuera de la transacción
///
/// Primero se mira, en un ámbito, que se pueda (los errores salen **antes** de
/// preguntar a la federación); después se pregunta, **fuera de todo ámbito**, porque
/// el acceso a los datos es de una conexión y la federación puede tardar segundos
/// (`D-100`, como el saneado de la foto); y al final se escribe todo en otro ámbito,
/// que es una transacción: si falla a mitad, no queda nada a medias.
///
/// # Lo que no toca
///
/// **El perfil de quien ya existía**: la sincronización no es el club guardando una
/// fila, así que no le copia nada (`D-122` es de los guardados). Si su dorsal estaba
/// cogido y su fila llega sin él, el perfil sigue recordándolo.
public struct SyncTeamRoster: Sendable {
    private let unitOfWork: any TenantUnitOfWork
    private let federations: any FederationClientProvider
    private let clock: any Clock
    private let ids: any UUIDProvider

    public init(unitOfWork: any TenantUnitOfWork, federations: any FederationClientProvider,
                clock: any Clock, ids: any UUIDProvider) {
        self.unitOfWork = unitOfWork
        self.federations = federations
        self.clock = clock
        self.ids = ids
    }

    public func execute(actor: ActorContext, teamID: TeamID, seasonID: SeasonID) async throws -> RosterSyncSummary {
        let now = clock.now()
        // 1 · Que se pueda, y con qué código.
        let plan = try await unitOfWork.withRepositories(actor: actor) { r in
            try await Self.plan(actor: actor, teamID: teamID, seasonID: seasonID, now: now, in: r)
        }
        guard let client = federations.client(for: plan.federation) else {
            throw ApplicationError.federationAdapterMissing(federation: plan.federation.rawValue)
        }
        // 2 · La federación, fuera de la transacción.
        let published = try await client.fetchTeamRoster(federationTeamID: plan.code)
        // 3 · Todo lo que se escribe, en una.
        let ids = self.ids
        return try await unitOfWork.withRepositories(actor: actor) { r in
            try await Self.apply(published, plan: plan, now: now, ids: ids, in: r)
        }
    }

    // ── 1 · Que se pueda ───────────────────────────────────────────────────────

    struct Plan: Sendable {
        let club: Club
        let federation: FederationCode
        let team: Team
        let season: Season
        /// La fila de la inscripción cuyo código se usa: la de la competición más
        /// antigua con código (decisión 6 de R6.14). En ella se apunta la fecha.
        let registration: TeamRegistration
        let code: String
    }

    static func plan(actor: ActorContext, teamID: TeamID, seasonID: SeasonID, now: Date,
                     in r: any Repositories) async throws -> Plan {
        guard let club = try await r.clubs.current() else {
            throw ApplicationError.tenantNotProvisioned(slug: actor.clubSlug.value)
        }
        guard let team = try await r.teams.find(teamID) else { throw ApplicationError.teamNotFound(id: "\(teamID)") }
        guard let season = try await r.seasons.find(seasonID) else {
            throw ApplicationError.unknownSeason(id: "\(seasonID)")
        }
        let rows = try await r.teamRegistrations.list(teamID: teamID, seasonID: seasonID)
        guard !rows.isEmpty else {
            throw ApplicationError.teamNotRegistered(team: "\(teamID)", season: "\(seasonID)")
        }
        // La archivada, de solo lectura (R6.3); y solo la en curso (decisión 1 de R6.14).
        try RosterRules.requireEditable(in: season)
        let all = try await r.seasons.list(includingArchived: false)
        guard all.current(on: now)?.id == season.id else {
            throw DomainError.seasonNotCurrent(label: season.label.value)
        }
        guard club.federation.capabilities.providesTeamRoster else {
            throw ApplicationError.federationRosterUnavailable(federation: club.federation.rawValue)
        }
        guard let registration = rows.filter({ $0.federationTeamID != nil }).min(by: { $0.createdAt < $1.createdAt }),
              let code = registration.federationTeamID
        else { throw ApplicationError.teamNotLinked(team: "\(teamID)", season: "\(seasonID)") }
        return Plan(club: club, federation: club.federation, team: team, season: season, registration: registration, code: code)
    }

    // ── 3 · Lo que se escribe ──────────────────────────────────────────────────

    static func apply(_ published: FederationTeamRoster, plan: Plan, now: Date, ids: any UUIDProvider,
                      in r: any Repositories) async throws -> RosterSyncSummary {
        let (team, season) = (plan.team, plan.season)
        var roster = try await r.players.list(teamID: team.id, seasonID: season.id)
        let deleted = try await r.players.deletedProfileIDs(teamID: team.id, seasonID: season.id)
        var profiles = try await r.playerProfiles.all()
        var summary = RosterSyncSummary(club: plan.club, syncedAt: now)
        var listed = Set<PlayerID>()

        for publishedPlayer in published.players {
            guard let raw = publishedPlayer.fullName, let name = try? PlayerName(raw) else {
                summary.invalidName.append(publishedPlayer.publishedName)
                continue
            }
            let matches = profiles.filter { $0.fullName.sameNameKey == name.sameNameKey }

            if matches.count == 1, let profile = matches.first {
                if let row = roster.first(where: { $0.profileID == profile.id }) {
                    summary.alreadyInRoster += 1
                    listed.insert(row.id)
                    continue
                }
                if deleted.contains(profile.id) {
                    summary.deletedInClub += 1
                    continue
                }
                if let elsewhere = try await r.players.list(profileID: profile.id, seasonID: season.id).first,
                   let otherTeam = try await r.teams.find(elsewhere.teamID) {
                    summary.inOtherTeam.append(.init(profile: profile, team: otherTeam))
                    continue
                }
                // Lo que guarda el perfil como ayuda (`D-122`); el dorsal, si está libre.
                let shirt = profile.lastShirtNumber.flatMap { number in
                    roster.contains { $0.shirtNumber == number } ? nil : number
                }
                let row = Player(
                    id: PlayerID(raw: ids.next()), profileID: profile.id, teamID: team.id, seasonID: season.id,
                    shirtNumber: shirt, position: profile.lastPosition, photoKey: profile.lastPhotoKey,
                    createdAt: now, updatedAt: now)
                try await r.players.save(row)
                roster.append(row)
                listed.insert(row.id)
                summary.added += 1
                if profile.birthYear == nil { summary.withoutBirthYear += 1 }
                continue
            }

            // Ninguno, o varios: perfil nuevo, sin año.
            let profile = PlayerProfile(id: PlayerProfileID(raw: ids.next()), fullName: name, birthYear: nil,
                                        createdAt: now, updatedAt: now)
            try await r.playerProfiles.save(profile)
            profiles.append(profile)
            let row = Player(id: PlayerID(raw: ids.next()), profileID: profile.id, teamID: team.id,
                             seasonID: season.id, createdAt: now, updatedAt: now)
            try await r.players.save(row)
            roster.append(row)
            listed.insert(row.id)
            summary.added += 1
            summary.withoutBirthYear += 1
            if matches.count > 1 { summary.duplicateName.append(.init(player: row, profile: profile)) }
        }

        // Federado o no, cada fila de la plantilla; la última vez listado, solo las listadas.
        for row in roster {
            let isListed = listed.contains(row.id)
            try await r.players.save(Player(
                id: row.id, profileID: row.profileID, teamID: row.teamID, seasonID: row.seasonID,
                shirtNumber: row.shirtNumber, position: row.position, photoKey: row.photoKey,
                federated: isListed, lastListedAt: isListed ? now : row.lastListedAt,
                createdAt: row.createdAt, updatedAt: now))
        }
        try await r.teamRegistrations.save(plan.registration.rosterSynced(at: now))
        return summary
    }
}

/// El resumen de la sincronización (`D-120`): lo que la web enseña al acabar.
public struct RosterSyncSummary: Equatable, Sendable {
    /// El club, para nombrar los equipos del resumen como en el resto de respuestas.
    public let club: Club
    public let syncedAt: Date
    /// Los añadidos, con perfil nuevo o con el que ya tenían.
    public var added = 0
    public var alreadyInRoster = 0
    /// De los añadidos, los que se quedan sin año.
    public var withoutBirthYear = 0
    /// Los que el club dio de baja de esta plantilla: no se vuelven a añadir.
    public var deletedInClub = 0
    /// Los añadidos con perfil nuevo porque su nombre casa con varios.
    public var duplicateName: [Added] = []
    /// Los que no se añaden porque están en otro equipo de la temporada (`D-121`).
    public var inOtherTeam: [Elsewhere] = []
    /// Los que no se añaden porque su nombre no vale, como lo escribe la federación.
    public var invalidName: [String] = []

    public init(club: Club, syncedAt: Date) {
        self.club = club
        self.syncedAt = syncedAt
    }

    public struct Added: Equatable, Sendable {
        public let player: Player
        public let profile: PlayerProfile
    }

    public struct Elsewhere: Equatable, Sendable {
        public let profile: PlayerProfile
        public let team: Team
    }
}
