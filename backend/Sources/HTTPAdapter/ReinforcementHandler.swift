public import APIContract
import Application
import Domain
import Foundation

/// `GET /v1/teams/{teamId}/registrations/{seasonId}/reinforcements` (R7.9, la
/// operación 89): los refuerzos de la plantilla, ya contados (`D-128`, punto 4). Los
/// 404 los traduce el middleware; aquí, los 400 de un id que no es un UUID.
extension APIHandler {
    public func listTeamReinforcements(_ input: Operations.listTeamReinforcements.Input) async throws
        -> Operations.listTeamReinforcements.Output
    {
        let actor = try actors.currentActor()
        let (teamID, seasonID): (TeamID, SeasonID)
        do {
            teamID = TeamID(raw: try Self.uuid(input.path.teamId, field: "teamId"))
            seasonID = SeasonID(raw: try Self.uuid(input.path.seasonId, field: "seasonId"))
        } catch let error as InvalidUUID {
            return .badRequest(Self.invalidUUID(error))
        }
        let rows = try await unitOfWork.withRepositories(actor: actor) { r in
            try await ListTeamReinforcements(
                clubs: r.clubs, seasons: r.seasons, teams: r.teams, opponentClubs: r.opponentClubs,
                registrations: r.teamRegistrations, players: r.players, profiles: r.playerProfiles,
                appearances: r.appearances, matches: r.matches, rounds: r.rounds
            ).execute(actor: actor, teamID: teamID, seasonID: seasonID)
        }
        return .ok(.init(body: .json(rows.map { $0.toResponse() })))
    }
}

extension Reinforcement {
    func toResponse() -> Components.Schemas.ReinforcementResponse {
        .init(
            playerId: "\(entry.player.id)", fullName: entry.profile.fullName.value,
            team: .init(value1: team.toTeamRef()), reportCount: reportCount, playedCount: playedCount,
            convokedWithoutMinutesCount: convokedWithoutMinutesCount,
            lastMatch: .init(value1: .init(
                matchId: "\(lastMatch.id)", roundNumber: lastRoundNumber,
                matchDate: lastMatch.kickoff.date.formatted(.isoDay))))
    }
}
