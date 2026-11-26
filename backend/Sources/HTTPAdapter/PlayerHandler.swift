public import APIContract
import Application
import Domain
import Foundation

// Las cinco operaciones de datos de la plantilla (R6.6). Los errores de dominio y
// de aplicación —404, 409, 422— los traduce el middleware (`A-14`·H-63); aquí solo
// se devuelven los 400 de un id que no es un UUID.
extension APIHandler {
    public func listPlayers(_ input: Operations.listPlayers.Input) async throws
        -> Operations.listPlayers.Output
    {
        let actor = try actors.currentActor()
        let (teamID, seasonID): (TeamID, SeasonID)
        do {
            teamID = TeamID(raw: try Self.uuid(input.query.teamId, field: "teamId"))
            seasonID = SeasonID(raw: try Self.uuid(input.query.seasonId, field: "seasonId"))
        } catch let error as InvalidUUID {
            return .badRequest(Self.invalidUUID(error))
        }
        let position = input.query.position?.toDomain()
        let roster = try await unitOfWork.withRepositories(actor: actor) { r in
            try await ListPlayers(teams: r.teams, seasons: r.seasons, players: r.players,
                                  profiles: r.playerProfiles)
                .execute(teamID: teamID, seasonID: seasonID, position: position)
        }
        return .ok(.init(body: .json(roster.map { $0.toResponse(photoURL) })))
    }

    public func getPlayer(_ input: Operations.getPlayer.Input) async throws
        -> Operations.getPlayer.Output
    {
        let actor = try actors.currentActor()
        let id: PlayerID
        do {
            id = PlayerID(raw: try Self.uuid(input.path.playerId, field: "playerId"))
        } catch let error as InvalidUUID {
            // El contrato no declara 400 aquí: un id que no es UUID no es de
            // ningún jugador, así que es el 404 de la ruta.
            return .notFound(.init(body: .application_problem_plus_json(
                Self.problem(status: 404, code: .PLAYER_NOT_FOUND,
                             title: "Jugador desconocido", detail: error.value))))
        }
        let entry = try await unitOfWork.withRepositories(actor: actor) { r in
            try await GetPlayer(players: r.players, profiles: r.playerProfiles).execute(id)
        }
        return .ok(.init(body: .json(entry.toResponse(photoURL))))
    }

    public func createPlayer(_ input: Operations.createPlayer.Input) async throws
        -> Operations.createPlayer.Output
    {
        let actor = try actors.currentActor()
        let payload: Components.Schemas.CreatePlayerRequest
        switch input.body {
        case .json(let json): payload = json
        }
        let command: CreatePlayer.Command
        do {
            switch payload {
            case .CreatePlayerFromProfileRequest(let body):
                command = .init(
                    teamID: TeamID(raw: try Self.uuid(body.teamId, field: "teamId")),
                    seasonID: SeasonID(raw: try Self.uuid(body.seasonId, field: "seasonId")),
                    who: .profile(PlayerProfileID(raw: try Self.uuid(body.profileId, field: "profileId"))),
                    shirtNumber: body.shirtNumber, position: body.position?.value1?.toDomain())
            case .CreatePlayerNewProfileRequest(let body):
                command = .init(
                    teamID: TeamID(raw: try Self.uuid(body.teamId, field: "teamId")),
                    seasonID: SeasonID(raw: try Self.uuid(body.seasonId, field: "seasonId")),
                    who: .newPlayer(fullName: body.fullName, birthYear: body.birthYear),
                    shirtNumber: body.shirtNumber, position: body.position?.value1?.toDomain())
            }
        } catch let error as InvalidUUID {
            return .badRequest(Self.invalidUUID(error))
        }
        let (clock, ids) = (self.clock, self.ids)
        let entry = try await unitOfWork.withRepositories(actor: actor) { r in
            try await CreatePlayer(teams: r.teams, seasons: r.seasons, players: r.players,
                                   profiles: r.playerProfiles, registrations: r.teamRegistrations,
                                   clock: clock, ids: ids)
                .execute(command)
        }
        return .created(.init(body: .json(entry.toResponse(photoURL))))
    }

    public func updatePlayer(_ input: Operations.updatePlayer.Input) async throws
        -> Operations.updatePlayer.Output
    {
        let actor = try actors.currentActor()
        let id: PlayerID
        do {
            id = PlayerID(raw: try Self.uuid(input.path.playerId, field: "playerId"))
        } catch let error as InvalidUUID {
            return .badRequest(Self.invalidUUID(error))
        }
        let body: Components.Schemas.UpdatePlayerRequest
        switch input.body {
        case .json(let json): body = json
        }
        // **La ficha entera** (R6.6): lo que no llega cuenta como vacío.
        let command = UpdatePlayer.Command(
            fullName: body.fullName, birthYear: body.birthYear, shirtNumber: body.shirtNumber,
            position: body.position?.value1?.toDomain())
        let clock = self.clock
        let entry = try await unitOfWork.withRepositories(actor: actor) { r in
            try await UpdatePlayer(seasons: r.seasons, players: r.players, profiles: r.playerProfiles,
                                   clock: clock).execute(id, command)
        }
        return .ok(.init(body: .json(entry.toResponse(photoURL))))
    }

    public func deletePlayer(_ input: Operations.deletePlayer.Input) async throws
        -> Operations.deletePlayer.Output
    {
        let actor = try actors.currentActor()
        let id: PlayerID
        do {
            id = PlayerID(raw: try Self.uuid(input.path.playerId, field: "playerId"))
        } catch let error as InvalidUUID {
            return .notFound(.init(body: .application_problem_plus_json(
                Self.problem(status: 404, code: .PLAYER_NOT_FOUND,
                             title: "Jugador desconocido", detail: error.value))))
        }
        let clock = self.clock
        try await unitOfWork.withRepositories(actor: actor) { r in
            try await DeletePlayer(seasons: r.seasons, players: r.players, clock: clock).execute(id)
        }
        return .noContent(.init())
    }
}

extension RosterEntry {
    /// Mapeo `Entidad → DTO` (§2.2): la fila, con el nombre y el año de su perfil
    /// (`D-119`).
    func toResponse(_ photoURL: (String?) -> String?) -> Components.Schemas.PlayerResponse {
        .init(
            id: "\(player.id)",
            profileId: "\(profile.id)",
            teamId: "\(player.teamID)",
            seasonId: "\(player.seasonID)",
            fullName: profile.fullName.value,
            birthYear: profile.birthYear?.value,
            shirtNumber: player.shirtNumber?.value,
            position: player.position.map { .init(value1: $0.toContract()) },
            // Los escribe la sincronización (`D-120`); nulos mientras esa plantilla
            // no se ha sincronizado nunca.
            federated: player.federated,
            lastListedAt: player.lastListedAt,
            // El enlace firmado, nuevo en cada lectura (`D-117`).
            photoUrl: photoURL(player.photoKey),
            createdAt: player.createdAt,
            updatedAt: player.updatedAt)
    }
}

extension Domain.PlayerPosition {
    /// El compilador obliga a escribir cada línea; `ContractEnumTests` comprueba
    /// que el viaje redondo es fiel (`C-E.9`).
    func toContract() -> Components.Schemas.PlayerPosition {
        switch self {
        case .portero: .portero
        case .defensa: .defensa
        case .centrocampista: .centrocampista
        case .delantero: .delantero
        }
    }
}

extension Components.Schemas.PlayerPosition {
    func toDomain() -> Domain.PlayerPosition {
        switch self {
        case .portero: .portero
        case .defensa: .defensa
        case .centrocampista: .centrocampista
        case .delantero: .delantero
        }
    }
}

// ── El buscador del alta (R6.7) ───────────────────────────────────────────────

extension APIHandler {
    public func searchPlayerProfiles(_ input: Operations.searchPlayerProfiles.Input) async throws
        -> Operations.searchPlayerProfiles.Output
    {
        let actor = try actors.currentActor()
        let (teamID, seasonID): (TeamID, SeasonID)
        do {
            teamID = TeamID(raw: try Self.uuid(input.query.teamId, field: "teamId"))
            seasonID = SeasonID(raw: try Self.uuid(input.query.seasonId, field: "seasonId"))
        } catch let error as InvalidUUID {
            return .badRequest(Self.invalidUUID(error))
        }
        // **Desde 3 letras** (`D-120`). El `minLength` del catálogo cuenta
        // caracteres y el generador no lo comprueba; las letras las cuenta
        // `PlayerSearch`, y con menos es un 400, como dice el contrato.
        guard let search = PlayerSearch(input.query.q) else {
            return .badRequest(.init(body: .application_problem_plus_json(
                Self.problem(status: 400, code: .BAD_REQUEST,
                             title: "Hacen falta tres letras",
                             detail: "q: desde \(PlayerSearch.minimumLetters) letras"))))
        }
        let matches = try await unitOfWork.withRepositories(actor: actor) { r in
            try await SearchPlayerProfiles(
                clubs: r.clubs, teams: r.teams, opponentClubs: r.opponentClubs, seasons: r.seasons,
                players: r.players, profiles: r.playerProfiles
            ).execute(search, teamID: teamID, seasonID: seasonID, actor: actor)
        }
        return .ok(.init(body: .json(matches.map { $0.toResponse(photoURL) })))
    }
}

extension SearchPlayerProfiles.Match {
    /// Mapeo `Entidad → DTO` (§2.2): el perfil entero (`D-122`), con su última
    /// plantilla y el otro equipo, si lo hay (`D-121`).
    func toResponse(_ photoURL: (String?) -> String?) -> Components.Schemas.PlayerProfileSearchResult {
        .init(
            profileId: "\(profile.id)",
            fullName: profile.fullName.value,
            birthYear: profile.birthYear?.value,
            lastShirtNumber: profile.lastShirtNumber?.value,
            lastPosition: profile.lastPosition.map { .init(value1: $0.toContract()) },
            lastPhotoUrl: photoURL(profile.lastPhotoKey),
            federationPlayerId: profile.federationPlayerID,
            lastRoster: lastRoster.map {
                .init(value1: .init(team: $0.team.toTeamRef(), seasonId: "\($0.season.id)",
                                    seasonLabel: $0.season.label.value))
            },
            otherTeamThisSeason: otherTeamThisSeason.map { .init(value1: $0.toTeamRef()) })
    }
}
