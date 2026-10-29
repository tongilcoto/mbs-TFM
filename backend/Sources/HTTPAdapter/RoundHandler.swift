public import APIContract
import Application
import Domain
import Foundation

/// `GET /v1/rounds?competitionId=` y `GET /v1/rounds/{roundId}` (§5.1, R4.6): las
/// jornadas de una competición, para la ficha del equipo y la pantalla de
/// jornada y clasificación del backoffice.
extension APIHandler {
    public func listRounds(_ input: Operations.listRounds.Input) async throws -> Operations.listRounds.Output {
        let actor = try actors.currentActor()
        // Sin `competitionId` no llega aquí: el código generado lo rechaza antes,
        // con el 400 `BAD_REQUEST` del middleware.
        let competitionID: CompetitionID
        do {
            competitionID = CompetitionID(raw: try Self.uuid(input.query.competitionId, field: "competitionId"))
        } catch let error as InvalidUUID {
            return .badRequest(Self.invalidUUID(error))
        }
        let clock = self.clock
        let listing = try await unitOfWork.withRepositories(actor: actor) { repositories in
            try await ListRounds(competitions: repositories.competitions, rounds: repositories.rounds, clock: clock)
                .execute(competitionID: competitionID)
        }
        return .ok(.init(body: .json(listing.rounds.map { $0.toResponse(isCurrent: $0.id == listing.currentID) })))
    }

    public func getRound(_ input: Operations.getRound.Input) async throws -> Operations.getRound.Output {
        let actor = try actors.currentActor()
        let roundID: RoundID
        do {
            roundID = RoundID(raw: try Self.uuid(input.path.roundId, field: "roundId"))
        } catch let error as InvalidUUID {
            return .badRequest(Self.invalidUUID(error))
        }
        let clock = self.clock
        // La que no existe la lanza el caso de uso (404 `ROUND_NOT_FOUND`).
        let result = try await unitOfWork.withRepositories(actor: actor) { repositories in
            try await GetRound(rounds: repositories.rounds, clock: clock).execute(roundID: roundID)
        }
        return .ok(.init(body: .json(result.round.toResponse(isCurrent: result.isCurrent))))
    }
}

extension Domain.Round {
    /// Mapeo `Entidad → DTO` (§2.2). `isCurrent` llega de fuera porque no es de
    /// la jornada sola: es de su competición, con el reloj (`[Round].current(on:)`).
    func toResponse(isCurrent: Bool) -> Components.Schemas.RoundResponse {
        .init(
            id: "\(id)",
            competitionId: "\(competitionID)",
            number: number,
            startDate: startDate.formatted(.isoDay),
            endDate: endDate.formatted(.isoDay),
            isCurrent: isCurrent,
            createdAt: createdAt,
            updatedAt: updatedAt)
    }
}
