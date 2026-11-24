public import APIContract
import Application
import Domain
import Foundation

// Las tarjetas del acta (R7.8). Los errores de dominio y de aplicación —404, 409,
// 422— los traduce el middleware (`A-14`·H-63); aquí solo los 400 de un id que no es
// un UUID y el ámbito.
extension APIHandler {
    public func listCards(_ input: Operations.listCards.Input) async throws -> Operations.listCards.Output {
        let actor = try actors.currentActor()
        let query = input.query
        func badRequest(_ code: Components.Schemas.ProblemCode, _ title: String, _ detail: String)
            -> Operations.listCards.Output
        {
            .badRequest(.init(body: .application_problem_plus_json(
                Self.problem(status: 400, code: code, title: title, detail: detail))))
        }
        // **El ámbito, obligatorio**: el partido, el jugador o los dos (`D-47`); `teamId`,
        // solo con el partido.
        guard query.matchId != nil || query.playerId != nil, query.teamId == nil || query.matchId != nil else {
            return badRequest(.MISSING_SCOPE, "Falta el ámbito de las tarjetas",
                              "Hace falta matchId, playerId o los dos; teamId va con matchId.")
        }
        let (matchID, playerID, teamID): (MatchID?, PlayerID?, TeamID?)
        do {
            matchID = try query.matchId.map { MatchID(raw: try Self.uuid($0, field: "matchId")) }
            playerID = try query.playerId.map { PlayerID(raw: try Self.uuid($0, field: "playerId")) }
            teamID = try query.teamId.map { TeamID(raw: try Self.uuid($0, field: "teamId")) }
        } catch let error as InvalidUUID {
            return badRequest(.INVALID_UUID, "`\(error.field)` no es un UUID", error.value)
        }
        let type = query._type?.toDomain()
        let cards = try await unitOfWork.withRepositories(actor: actor) { r in
            try await ListCards(matches: r.matches, teams: r.teams, players: r.players, cards: r.cards)
                .execute(matchID: matchID, playerID: playerID, teamID: teamID, type: type)
        }
        return .ok(.init(body: .json(cards.map { $0.toResponse() })))
    }

    public func getCard(_ input: Operations.getCard.Input) async throws -> Operations.getCard.Output {
        let actor = try actors.currentActor()
        guard let id = Self.cardID(input.path.cardId) else { return .notFound(Self.cardNotFound(input.path.cardId)) }
        let card = try await unitOfWork.withRepositories(actor: actor) { r in
            try await GetCard(cards: r.cards).execute(id)
        }
        return .ok(.init(body: .json(card.toResponse())))
    }

    public func createCard(_ input: Operations.createCard.Input) async throws -> Operations.createCard.Output {
        let actor = try actors.currentActor()
        let body: Components.Schemas.CreateCardRequest
        switch input.body {
        case .json(let json): body = json
        }
        let command: CreateCard.Command
        do {
            command = .init(
                playerID: PlayerID(raw: try Self.uuid(body.playerId, field: "playerId")),
                matchID: MatchID(raw: try Self.uuid(body.matchId, field: "matchId")),
                teamID: TeamID(raw: try Self.uuid(body.teamId, field: "teamId")),
                type: body._type.toDomain(), isSecondYellow: body.isSecondYellow ?? false,
                minute: body.minute, comment: body.comment)
        } catch let error as InvalidUUID {
            return .badRequest(Self.invalidUUID(error))
        }
        let (clock, ids) = (self.clock, self.ids)
        let card = try await unitOfWork.withRepositories(actor: actor) { r in
            try await CreateCard(repositories: Self.cardRepositories(r), clock: clock, ids: ids).execute(command)
        }
        return .created(.init(body: .json(card.toResponse())))
    }

    public func updateCard(_ input: Operations.updateCard.Input) async throws -> Operations.updateCard.Output {
        let actor = try actors.currentActor()
        let id: CardID
        do {
            id = CardID(raw: try Self.uuid(input.path.cardId, field: "cardId"))
        } catch let error as InvalidUUID {
            return .badRequest(Self.invalidUUID(error))
        }
        let body: Components.Schemas.UpdateCardRequest
        switch input.body {
        case .json(let json): body = json
        }
        // **Lo que no llega no cambia, y un `null` tampoco** (R7.6, `D-65`).
        let command = UpdateCard.Command(type: body._type?.toDomain(), isSecondYellow: body.isSecondYellow,
                                         minute: body.minute, comment: body.comment)
        guard !command.isEmpty else {
            return .badRequest(.init(body: .application_problem_plus_json(Self.problem(
                status: 400, code: .EMPTY_PATCH, title: "El cuerpo debe traer al menos un campo",
                detail: "minProperties: 1"))))
        }
        let clock = self.clock
        let card = try await unitOfWork.withRepositories(actor: actor) { r in
            try await UpdateCard(repositories: Self.cardRepositories(r), clock: clock).execute(id, command)
        }
        return .ok(.init(body: .json(card.toResponse())))
    }

    public func deleteCard(_ input: Operations.deleteCard.Input) async throws -> Operations.deleteCard.Output {
        let actor = try actors.currentActor()
        guard let id = Self.cardID(input.path.cardId) else { return .notFound(Self.cardNotFound(input.path.cardId)) }
        try await unitOfWork.withRepositories(actor: actor) { r in
            try await DeleteCard(repositories: Self.cardRepositories(r)).execute(id)
        }
        return .noContent(.init())
    }

    // ── Ayudantes ───────────────────────────────────────────────────────────

    static func cardRepositories(_ r: any Repositories) -> CardRepositories {
        CardRepositories(matches: r.matches, competitions: r.competitions, seasons: r.seasons, teams: r.teams,
                         players: r.players, cards: r.cards)
    }

    /// Un id que no es UUID no es de ninguna tarjeta: el 404 de la ruta.
    static func cardID(_ raw: String) -> CardID? {
        (try? Self.uuid(raw, field: "cardId")).map(CardID.init(raw:))
    }

    static func cardNotFound(_ raw: String) -> Components.Responses.NotFound {
        .init(body: .application_problem_plus_json(
            Self.problem(status: 404, code: .CARD_NOT_FOUND, title: "Tarjeta desconocida", detail: raw)))
    }
}

extension Card {
    func toResponse() -> Components.Schemas.CardResponse {
        .init(id: "\(id)", playerId: "\(playerID)", matchId: "\(matchID)", teamId: "\(teamID)",
              _type: type.toContract(), isSecondYellow: isSecondYellow, minute: minute?.value,
              comment: comment?.value, fromReport: fromReport, createdAt: createdAt, updatedAt: updatedAt)
    }
}

extension Domain.CardType {
    func toContract() -> Components.Schemas.CardType {
        switch self {
        case .amarilla: .amarilla
        case .roja: .roja
        }
    }
}

extension Components.Schemas.CardType {
    func toDomain() -> Domain.CardType {
        switch self {
        case .amarilla: .amarilla
        case .roja: .roja
        }
    }
}
