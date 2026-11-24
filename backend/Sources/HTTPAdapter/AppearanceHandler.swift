public import APIContract
import Application
import Domain
import Foundation

// La cabecera del acta y la convocatoria (R7.6). Los errores de dominio y de
// aplicación —404, 409, 422— los traduce el middleware (`A-14`·H-63); aquí solo
// los 400 de un id que no es un UUID, y el ámbito.
extension APIHandler {
    public func getMatch(_ input: Operations.getMatch.Input) async throws -> Operations.getMatch.Output {
        let actor = try actors.currentActor()
        let id: MatchID
        do {
            id = MatchID(raw: try Self.uuid(input.path.matchId, field: "matchId"))
        } catch let error as InvalidUUID {
            // Sin 400 en el contrato: un id que no es UUID no es de ningún partido.
            return .notFound(.init(body: .application_problem_plus_json(
                Self.problem(status: 404, code: .MATCH_NOT_FOUND, title: "Partido desconocido",
                             detail: error.value))))
        }
        let detail = try await unitOfWork.withRepositories(actor: actor) { r in
            try await GetMatch(
                clubs: r.clubs, seasons: r.seasons, competitions: r.competitions, rounds: r.rounds,
                matches: r.matches, standingRows: r.standingRows, teams: r.teams, opponentClubs: r.opponentClubs,
                appearances: r.appearances
            ).execute(actor: actor, id: id)
        }
        var match = detail.line.toResponse()
        match.reportLoadedAt = detail.reportLoadedAt
        return .ok(.init(body: .json(.init(
            value1: match,
            value2: .init(removedFromReport: detail.removedFromReport.map { $0.toResponse() })))))
    }

    public func listAppearances(_ input: Operations.listAppearances.Input) async throws
        -> Operations.listAppearances.Output
    {
        let actor = try actors.currentActor()
        let query = input.query
        // **Dos puertas, y exactamente una** (`D-43`); `teamId`, solo con el partido.
        guard (query.matchId == nil) != (query.playerId == nil), query.teamId == nil || query.matchId != nil else {
            return .badRequest(.init(body: .application_problem_plus_json(Self.problem(
                status: 400, code: .MISSING_SCOPE, title: "Falta el ámbito de la convocatoria",
                detail: "Hace falta matchId o playerId, uno solo; teamId va con matchId."))))
        }
        let scope: ListAppearances.Scope
        do {
            if let matchId = query.matchId {
                scope = .match(MatchID(raw: try Self.uuid(matchId, field: "matchId")),
                               teamID: try query.teamId.map { TeamID(raw: try Self.uuid($0, field: "teamId")) })
            } else {
                scope = .player(PlayerID(raw: try Self.uuid(query.playerId ?? "", field: "playerId")))
            }
        } catch let error as InvalidUUID {
            return .badRequest(.init(body: .application_problem_plus_json(Self.problem(
                status: 400, code: .INVALID_UUID, title: "`\(error.field)` no es un UUID", detail: error.value))))
        }
        let status = query.status?.toDomain()
        let rows = try await unitOfWork.withRepositories(actor: actor) { r in
            try await ListAppearances(matches: r.matches, teams: r.teams, players: r.players,
                                      appearances: r.appearances).execute(scope, status: status)
        }
        return .ok(.init(body: .json(rows.map { $0.toResponse() })))
    }

    public func getAppearance(_ input: Operations.getAppearance.Input) async throws
        -> Operations.getAppearance.Output
    {
        let actor = try actors.currentActor()
        guard let id = Self.appearanceID(input.path.appearanceId) else {
            return .notFound(Self.appearanceNotFound(input.path.appearanceId))
        }
        let line = try await unitOfWork.withRepositories(actor: actor) { r in
            try await GetAppearance(matches: r.matches, appearances: r.appearances).execute(id)
        }
        return .ok(.init(body: .json(line.toResponse())))
    }

    public func createAppearance(_ input: Operations.createAppearance.Input) async throws
        -> Operations.createAppearance.Output
    {
        let actor = try actors.currentActor()
        let body: Components.Schemas.CreateAppearanceRequest
        switch input.body {
        case .json(let json): body = json
        }
        let command: CreateAppearance.Command
        do {
            command = .init(
                playerID: PlayerID(raw: try Self.uuid(body.playerId, field: "playerId")),
                matchID: MatchID(raw: try Self.uuid(body.matchId, field: "matchId")),
                teamID: TeamID(raw: try Self.uuid(body.teamId, field: "teamId")),
                status: body.status.toDomain(), shirtNumber: body.shirtNumber, minutes: body.minutes)
        } catch let error as InvalidUUID {
            return .badRequest(Self.invalidUUID(error))
        }
        let (clock, ids) = (self.clock, self.ids)
        let line = try await unitOfWork.withRepositories(actor: actor) { r in
            try await CreateAppearance(repositories: Self.appearanceRepositories(r), clock: clock, ids: ids)
                .execute(command)
        }
        return .created(.init(body: .json(line.toResponse())))
    }

    public func updateAppearance(_ input: Operations.updateAppearance.Input) async throws
        -> Operations.updateAppearance.Output
    {
        let actor = try actors.currentActor()
        let id: AppearanceID
        do {
            id = AppearanceID(raw: try Self.uuid(input.path.appearanceId, field: "appearanceId"))
        } catch let error as InvalidUUID {
            return .badRequest(Self.invalidUUID(error))
        }
        let body: Components.Schemas.UpdateAppearanceRequest
        switch input.body {
        case .json(let json): body = json
        }
        // **Un campo que no llega no cambia, y un `null` tampoco** (R7.6): el
        // generador no los distingue (`D-65`).
        let command = UpdateAppearance.Command(
            status: body.status?.toDomain(), shirtNumber: body.shirtNumber, minutes: body.minutes)
        // `minProperties: 1`, que el generador ignora (`D-65`): un `PATCH {}` no pide nada.
        guard !command.isEmpty else {
            return .badRequest(.init(body: .application_problem_plus_json(Self.problem(
                status: 400, code: .EMPTY_PATCH, title: "El cuerpo debe traer al menos un campo",
                detail: "minProperties: 1"))))
        }
        let clock = self.clock
        let line = try await unitOfWork.withRepositories(actor: actor) { r in
            try await UpdateAppearance(repositories: Self.appearanceRepositories(r), clock: clock)
                .execute(id, command)
        }
        return .ok(.init(body: .json(line.toResponse())))
    }

    public func deleteAppearance(_ input: Operations.deleteAppearance.Input) async throws
        -> Operations.deleteAppearance.Output
    {
        let actor = try actors.currentActor()
        guard let id = Self.appearanceID(input.path.appearanceId) else {
            return .notFound(Self.appearanceNotFound(input.path.appearanceId))
        }
        try await unitOfWork.withRepositories(actor: actor) { r in
            try await DeleteAppearance(repositories: Self.appearanceRepositories(r)).execute(id)
        }
        return .noContent(.init())
    }

    // ── Ayudantes ───────────────────────────────────────────────────────────

    static func appearanceRepositories(_ r: any Repositories) -> AppearanceRepositories {
        AppearanceRepositories(matches: r.matches, competitions: r.competitions, seasons: r.seasons,
                               teams: r.teams, players: r.players, appearances: r.appearances)
    }

    /// Un id que no es UUID no es de ninguna convocatoria: el 404 de la ruta, como
    /// en `getPlayer`, donde el contrato no declara 400.
    static func appearanceID(_ raw: String) -> AppearanceID? {
        (try? Self.uuid(raw, field: "appearanceId")).map(AppearanceID.init(raw:))
    }

    static func appearanceNotFound(_ raw: String) -> Components.Responses.NotFound {
        .init(body: .application_problem_plus_json(
            Self.problem(status: 404, code: .APPEARANCE_NOT_FOUND, title: "Convocatoria desconocida",
                         detail: raw)))
    }
}

extension AppearanceLine {
    func toResponse() -> Components.Schemas.AppearanceResponse {
        .init(
            id: "\(appearance.id)", playerId: "\(appearance.playerID)", matchId: "\(appearance.matchID)",
            teamId: "\(appearance.teamID)", status: appearance.status.toContract(),
            shirtNumber: appearance.shirtNumber?.value, changedFromReport: changedFromReport,
            minutes: appearance.minutes?.value, createdAt: appearance.createdAt, updatedAt: appearance.updatedAt)
    }
}

extension ReportLineupEntry {
    func toResponse() -> Components.Schemas.ReportLineupEntry {
        .init(playerId: "\(playerID)", teamId: "\(teamID)", status: status.toContract())
    }
}

extension Domain.AppearanceStatus {
    func toContract() -> Components.Schemas.AppearanceStatus {
        switch self {
        case .convocadoSinMinutos: .convocado_sin_minutos
        case .jugado: .jugado
        case .bajaMedica: .baja_medica
        case .sancionado: .sancionado
        }
    }
}

extension Components.Schemas.AppearanceStatus {
    func toDomain() -> Domain.AppearanceStatus {
        switch self {
        case .convocado_sin_minutos: .convocadoSinMinutos
        case .jugado: .jugado
        case .baja_medica: .bajaMedica
        case .sancionado: .sancionado
        }
    }
}
