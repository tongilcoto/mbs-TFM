public import APIContract
import Application
import Domain
import Foundation

/// `GET /v1/standings?roundId=` (§5.1, `D-34`, R4.7): la clasificación de una
/// jornada, por puesto, con la racha de cada equipo.
extension APIHandler {
    public func getStanding(_ input: Operations.getStanding.Input) async throws -> Operations.getStanding.Output {
        let actor = try actors.currentActor()
        // Sin `roundId` no llega aquí: el código generado lo rechaza antes, con
        // el 400 `BAD_REQUEST` del middleware.
        let roundID: RoundID
        do {
            roundID = RoundID(raw: try Self.uuid(input.query.roundId, field: "roundId"))
        } catch let error as InvalidUUID {
            return .badRequest(Self.invalidUUID(error))
        }
        // La jornada que no existe la lanza el caso de uso (404 `ROUND_NOT_FOUND`).
        let lines = try await unitOfWork.withRepositories(actor: actor) { repositories in
            try await GetStanding(
                clubs: repositories.clubs, rounds: repositories.rounds, standingRows: repositories.standingRows,
                matches: repositories.matches, teams: repositories.teams, opponentClubs: repositories.opponentClubs
            ).execute(actor: actor, roundID: roundID)
        }
        return .ok(.init(body: .json(lines.map { $0.toResponse() })))
    }
}

extension GetStanding.Line {
    /// Mapeo `Caso de uso → DTO` (§2.2): la fila guardada, su equipo como
    /// `TeamRef` y la racha.
    func toResponse() -> Components.Schemas.StandingResponse {
        .init(
            id: "\(row.id)",
            competitionId: "\(row.competitionID)",
            roundId: "\(row.roundID)",
            team: .init(value1: team.toTeamRef()),
            position: row.position,
            previousPosition: row.previousPosition,
            played: row.played,
            won: row.won,
            drawn: row.drawn,
            lost: row.lost,
            goalsFor: row.goalsFor,
            goalsAgainst: row.goalsAgainst,
            points: row.points,
            form: form.map { .init(roundNumber: $0.roundNumber, outcome: .init(value1: $0.outcome.toContract())) },
            createdAt: row.createdAt,
            updatedAt: row.updatedAt)
    }
}

extension Domain.TeamOutcome {
    func toContract() -> Components.Schemas.MatchOutcome {
        switch self {
        case .win: .victoria
        case .draw: .empate
        case .loss: .derrota
        }
    }
}

extension LabeledTeam {
    /// Mapeo a `TeamRef` (`D-32`), con los derivados compuestos como en
    /// `TeamResponse` (§3.6, `D-109`): `displayName` es el nombre corto del club
    /// + categoría + letra; `shortDisplayName`, sin la categoría; y
    /// `nameWithLetter`, el nombre del club, no el corto, + letra (`D-111`). El
    /// club es el propio o el rival.
    func toTeamRef() -> Components.Schemas.TeamRef {
        .init(
            teamId: "\(team.id)",
            displayName: [clubShortName, team.category.toContract().displayName, team.letter]
                .compactMap { $0 }.joined(separator: " "),
            shortDisplayName: [clubShortName, team.letter].compactMap { $0 }.joined(separator: " "),
            nameWithLetter: [clubName, team.letter].compactMap { $0 }.joined(separator: " "),
            crestUrl: nil,
            isOwn: team.isOwn)
    }
}
