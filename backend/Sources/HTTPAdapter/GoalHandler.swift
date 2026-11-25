public import APIContract
import Application
import Domain
import Foundation

// Los goles del acta (R7.7). Los errores de dominio y de aplicación —404, 422— los
// traduce el middleware (`A-14`·H-63); aquí solo los 400 de un id que no es un
// UUID, el ámbito y la página.
extension APIHandler {
    public func listGoals(_ input: Operations.listGoals.Input) async throws -> Operations.listGoals.Output {
        let actor = try actors.currentActor()
        let query = input.query
        func badRequest(_ code: Components.Schemas.ProblemCode, _ title: String, _ detail: String)
            -> Operations.listGoals.Output
        {
            .badRequest(.init(body: .application_problem_plus_json(
                Self.problem(status: 400, code: code, title: title, detail: detail))))
        }
        // `page` y `perPage` los comprueba el adaptador: el generador ignora los
        // límites (`D-65`).
        let (page, perPage) = (query.page ?? 1, query.perPage ?? 25)
        guard page >= 1, (1...100).contains(perPage) else {
            return badRequest(.BAD_REQUEST, "Página fuera de rango", "page empieza en 1, y perPage va de 1 a 100.")
        }
        let filter: GoalFilter
        do {
            func id<T>(_ raw: String?, _ field: String, _ make: (UUID) -> T) throws -> T? {
                try raw.map { make(try Self.uuid($0, field: field)) }
            }
            filter = GoalFilter(
                matchID: try id(query.matchId, "matchId", MatchID.init(raw:)),
                scoringTeamID: try id(query.scoringTeamId, "scoringTeamId", TeamID.init(raw:)),
                concedingTeamID: try id(query.concedingTeamId, "concedingTeamId", TeamID.init(raw:)),
                scorer: try id(query.scorerPlayerId, "scorerPlayerId", PlayerID.init(raw:)),
                assist: try id(query.assistPlayerId, "assistPlayerId", PlayerID.init(raw:)),
                seasonID: try id(query.seasonId, "seasonId", SeasonID.init(raw:)),
                playType: query.playType?.toDomain())
        } catch let error as InvalidUUID {
            return badRequest(.INVALID_UUID, "`\(error.field)` no es un UUID", error.value)
        }
        // **El ámbito, obligatorio** (§5.1): una de las cuatro puertas.
        guard filter.hasScope else {
            return badRequest(.MISSING_SCOPE, "Falta el ámbito de los goles",
                              "Hace falta matchId, scoringTeamId, concedingTeamId o scorerPlayerId.")
        }
        let result = try await unitOfWork.withRepositories(actor: actor) { r in
            try await ListGoals(matches: r.matches, teams: r.teams, players: r.players, seasons: r.seasons,
                                goals: r.goals).execute(filter, page: page, perPage: perPage)
        }
        return .ok(.init(body: .json(.init(
            value1: .init(page: result.page, perPage: result.perPage, total: result.total),
            value2: .init(data: result.goals.map { $0.toResponse() })))))
    }

    public func getGoal(_ input: Operations.getGoal.Input) async throws -> Operations.getGoal.Output {
        let actor = try actors.currentActor()
        guard let id = Self.goalID(input.path.goalId) else { return .notFound(Self.goalNotFound(input.path.goalId)) }
        let goal = try await unitOfWork.withRepositories(actor: actor) { r in
            try await GetGoal(goals: r.goals).execute(id)
        }
        return .ok(.init(body: .json(goal.toResponse())))
    }

    public func createGoal(_ input: Operations.createGoal.Input) async throws -> Operations.createGoal.Output {
        let actor = try actors.currentActor()
        let body: Components.Schemas.CreateGoalRequest
        switch input.body {
        case .json(let json): body = json
        }
        let (matchID, teamID, fields): (MatchID, TeamID, GoalFields)
        do {
            matchID = MatchID(raw: try Self.uuid(body.matchId, field: "matchId"))
            teamID = TeamID(raw: try Self.uuid(body.scoringTeamId, field: "scoringTeamId"))
            fields = try Self.goalFields(
                scorer: body.scorerPlayerId, assist: body.assistPlayerId, assisted: body.assisted,
                minute: body.minute, zone: body.zone, attackSide: body.attackSide, shotSide: body.shotSide,
                bodyPart: body.bodyPart, playType: body.playType, comment: body.comment)
        } catch let error as InvalidUUID {
            return .badRequest(Self.invalidUUID(error))
        }
        let (clock, ids) = (self.clock, self.ids)
        let goal = try await unitOfWork.withRepositories(actor: actor) { r in
            try await CreateGoal(repositories: Self.goalRepositories(r), clock: clock, ids: ids)
                .execute(matchID: matchID, scoringTeamID: teamID, fields)
        }
        return .created(.init(body: .json(goal.toResponse())))
    }

    public func updateGoal(_ input: Operations.updateGoal.Input) async throws -> Operations.updateGoal.Output {
        let actor = try actors.currentActor()
        let body: Components.Schemas.UpdateGoalRequest
        switch input.body {
        case .json(let json): body = json
        }
        let (id, fields): (GoalID, GoalFields)
        do {
            id = GoalID(raw: try Self.uuid(input.path.goalId, field: "goalId"))
            fields = try Self.goalFields(
                scorer: body.scorerPlayerId, assist: body.assistPlayerId, assisted: body.assisted,
                minute: body.minute, zone: body.zone, attackSide: body.attackSide, shotSide: body.shotSide,
                bodyPart: body.bodyPart, playType: body.playType, comment: body.comment)
        } catch let error as InvalidUUID {
            return .badRequest(Self.invalidUUID(error))
        }
        // `minProperties: 1`, que el generador ignora (`D-65`).
        guard !fields.isEmpty else {
            return .badRequest(.init(body: .application_problem_plus_json(Self.problem(
                status: 400, code: .EMPTY_PATCH, title: "El cuerpo debe traer al menos un campo",
                detail: "minProperties: 1"))))
        }
        let clock = self.clock
        let goal = try await unitOfWork.withRepositories(actor: actor) { r in
            try await UpdateGoal(repositories: Self.goalRepositories(r), clock: clock).execute(id, fields)
        }
        return .ok(.init(body: .json(goal.toResponse())))
    }

    public func deleteGoal(_ input: Operations.deleteGoal.Input) async throws -> Operations.deleteGoal.Output {
        let actor = try actors.currentActor()
        guard let id = Self.goalID(input.path.goalId) else { return .notFound(Self.goalNotFound(input.path.goalId)) }
        try await unitOfWork.withRepositories(actor: actor) { r in
            try await DeleteGoal(repositories: Self.goalRepositories(r)).execute(id)
        }
        return .noContent(.init())
    }

    // ── Ayudantes ───────────────────────────────────────────────────────────

    static func goalRepositories(_ r: any Repositories) -> GoalRepositories {
        GoalRepositories(matches: r.matches, competitions: r.competitions, seasons: r.seasons, teams: r.teams,
                         players: r.players, goals: r.goals)
    }

    static func goalFields(
        scorer: String?, assist: String?, assisted: Bool?, minute: Int?, zone: Components.Schemas.GoalZone?,
        attackSide: Components.Schemas.GoalSide?, shotSide: Components.Schemas.GoalSide?,
        bodyPart: Components.Schemas.GoalBodyPart?, playType: Components.Schemas.GoalPlayType?, comment: String?
    ) throws -> GoalFields {
        GoalFields(
            scorer: try scorer.map { PlayerID(raw: try Self.uuid($0, field: "scorerPlayerId")) },
            assist: try assist.map { PlayerID(raw: try Self.uuid($0, field: "assistPlayerId")) },
            assisted: assisted, minute: minute, zone: zone?.toDomain(), attackSide: attackSide?.toDomain(),
            shotSide: shotSide?.toDomain(), bodyPart: bodyPart?.toDomain(), playType: playType?.toDomain(),
            comment: comment)
    }

    /// Un id que no es UUID no es de ningún gol: el 404 de la ruta.
    static func goalID(_ raw: String) -> GoalID? {
        (try? Self.uuid(raw, field: "goalId")).map(GoalID.init(raw:))
    }

    static func goalNotFound(_ raw: String) -> Components.Responses.NotFound {
        .init(body: .application_problem_plus_json(
            Self.problem(status: 404, code: .GOAL_NOT_FOUND, title: "Gol desconocido", detail: raw)))
    }
}

extension Goal {
    func toResponse() -> Components.Schemas.GoalResponse {
        .init(
            id: "\(id)", matchId: "\(matchID)", scoringTeamId: "\(scoringTeamID)",
            concedingTeamId: "\(concedingTeamID)", scorerPlayerId: scorer.map { "\($0)" },
            assistPlayerId: assist.map { "\($0)" }, assisted: assisted, minute: minute?.value,
            zone: zone?.toContract(), attackSide: attackSide?.toContract(), shotSide: shotSide?.toContract(),
            bodyPart: bodyPart?.toContract(), playType: playType?.toContract(), comment: comment?.value,
            fromReport: fromReport, createdAt: createdAt, updatedAt: updatedAt)
    }
}

// ── Los enumerados del gol, de ida y de vuelta ──────────────────────────────

extension Domain.GoalZone {
    func toContract() -> Components.Schemas.GoalZone {
        switch self {
        case .areaChica: .area_chica
        case .areaPenalti: .area_penalti
        case .fueraArea: .fuera_area
        }
    }
}

extension Components.Schemas.GoalZone {
    func toDomain() -> Domain.GoalZone {
        switch self {
        case .area_chica: .areaChica
        case .area_penalti: .areaPenalti
        case .fuera_area: .fueraArea
        }
    }
}

extension Domain.GoalSide {
    func toContract() -> Components.Schemas.GoalSide {
        switch self {
        case .derecha: .derecha
        case .izquierda: .izquierda
        case .centro: .centro
        }
    }
}

extension Components.Schemas.GoalSide {
    func toDomain() -> Domain.GoalSide {
        switch self {
        case .derecha: .derecha
        case .izquierda: .izquierda
        case .centro: .centro
        }
    }
}

extension Domain.GoalBodyPart {
    func toContract() -> Components.Schemas.GoalBodyPart {
        switch self {
        case .pieIzquierdo: .pie_izquierdo
        case .pieDerecho: .pie_derecho
        case .cabeza: .cabeza
        case .otro: .otro
        }
    }
}

extension Components.Schemas.GoalBodyPart {
    func toDomain() -> Domain.GoalBodyPart {
        switch self {
        case .pie_izquierdo: .pieIzquierdo
        case .pie_derecho: .pieDerecho
        case .cabeza: .cabeza
        case .otro: .otro
        }
    }
}

extension Domain.GoalPlayType {
    func toContract() -> Components.Schemas.GoalPlayType {
        switch self {
        case .juegoAbierto: .juego_abierto
        case .faltaDirecta: .falta_directa
        case .trasFalta: .tras_falta
        case .trasCorner: .tras_corner
        case .penalti: .penalti
        case .enPropiaPuerta: .en_propia_puerta
        }
    }
}

extension Components.Schemas.GoalPlayType {
    func toDomain() -> Domain.GoalPlayType {
        switch self {
        case .juego_abierto: .juegoAbierto
        case .falta_directa: .faltaDirecta
        case .tras_falta: .trasFalta
        case .tras_corner: .trasCorner
        case .penalti: .penalti
        case .en_propia_puerta: .enPropiaPuerta
        }
    }
}
