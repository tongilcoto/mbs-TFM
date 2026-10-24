public import APIContract
import Application
import Domain
import Foundation

/// `POST /v1/teams` (§5.1, R2.9): el alta de un equipo del club, que lo inscribe
/// en la temporada; y si ya existe, solo lo inscribe (`D-107`).
extension APIHandler {
    public func createTeam(_ input: Operations.createTeam.Input) async throws
        -> Operations.createTeam.Output
    {
        let actor = try actors.currentActor()
        let payload: Components.Schemas.CreateTeamRequest
        switch input.body {
        case .json(let json): payload = json
        }
        let seasonID: SeasonID
        do {
            seasonID = SeasonID(raw: try Self.uuid(payload.seasonId, field: "seasonId"))
        } catch let error as InvalidUUID {
            return .badRequest(Self.invalidUUID(error))
        }
        let command = CreateTeam.Command(
            category: payload.category.toDomain(), letter: payload.letter,
            gender: payload.gender.toDomain(), modality: payload.modality.toDomain(),
            seasonID: seasonID)
        let (clock, ids) = (self.clock, self.ids)

        // **Sin `do/catch`** (`A-14`·H-63): el 404 de la temporada, el 409 de «ya
        // inscrito» y el 422 de la letra en blanco los traduce el middleware.
        let result = try await unitOfWork.withRepositories(actor: actor) { repositories in
            try await CreateTeam(
                clubs: repositories.clubs, seasons: repositories.seasons,
                teams: repositories.teams, registrations: repositories.teamRegistrations,
                clock: clock, ids: ids
            ).execute(command, actor: actor)
        }
        let body = result.team.toResponse(club: result.club)
        // **201 si se creó, 200 si ya existía y solo se ha inscrito** (`D-107`).
        return result.created
            ? .created(.init(body: .json(body)))
            : .ok(.init(body: .json(body)))
    }
}
