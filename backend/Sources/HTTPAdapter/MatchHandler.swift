public import APIContract
import Application
import Domain
import Foundation

/// `GET /v1/matches` (§5.1, R4.8): los partidos de una jornada, de una
/// competición o de un equipo, paginados y en orden de calendario.
extension APIHandler {
    public func listMatches(_ input: Operations.listMatches.Input) async throws -> Operations.listMatches.Output {
        let actor = try actors.currentActor()
        let query = input.query
        // **El ámbito, obligatorio** (§5.1): la temporada sola no basta.
        guard query.roundId != nil || query.competitionId != nil || query.teamId != nil else {
            return .badRequest(.init(body: .application_problem_plus_json(Self.problem(
                status: 400, code: .MISSING_SCOPE, title: "Falta el ámbito de los partidos",
                detail: "Hace falta roundId, competitionId o teamId; seasonId solo acota."))))
        }
        // **`page` y `perPage` los comprueba aquí el adaptador**, porque el
        // generador ignora `minimum` y `maximum` (`D-65`).
        let (page, perPage) = (query.page ?? 1, query.perPage ?? 25)
        guard page >= 1, (1...100).contains(perPage) else {
            return .badRequest(.init(body: .application_problem_plus_json(Self.problem(
                status: 400, code: .BAD_REQUEST, title: "Página fuera de rango",
                detail: "page empieza en 1, y perPage va de 1 a 100."))))
        }
        let matchQuery: ListMatches.Query
        do {
            matchQuery = ListMatches.Query(
                roundID: try query.roundId.map { RoundID(raw: try Self.uuid($0, field: "roundId")) },
                competitionID: try query.competitionId.map { CompetitionID(raw: try Self.uuid($0, field: "competitionId")) },
                teamID: try query.teamId.map { TeamID(raw: try Self.uuid($0, field: "teamId")) },
                seasonID: try query.seasonId.map { SeasonID(raw: try Self.uuid($0, field: "seasonId")) },
                status: query.status?.toDomain(), newestFirst: query.order == .desc, page: page, perPage: perPage)
        } catch let error as InvalidUUID {
            return .badRequest(Self.invalidUUID(error))
        }
        // Los 404 de cada ámbito los lanza el caso de uso.
        let result = try await unitOfWork.withRepositories(actor: actor) { repositories in
            try await ListMatches(
                clubs: repositories.clubs, seasons: repositories.seasons, competitions: repositories.competitions,
                rounds: repositories.rounds, matches: repositories.matches, standingRows: repositories.standingRows,
                teams: repositories.teams, opponentClubs: repositories.opponentClubs
            ).execute(actor: actor, query: matchQuery)
        }
        return .ok(.init(body: .json(.init(
            value1: .init(page: result.page, perPage: result.perPage, total: result.total),
            value2: .init(data: result.lines.map { $0.toResponse() })))))
    }
}

extension ListMatches.Line {
    /// Mapeo `Caso de uso → DTO` (§2.2): el partido, con la fecha como día y la
    /// hora como `HH:MM` (o nula, sin fijar, `D-30`), y cada lado con su equipo,
    /// su marcador y su fila de la clasificación de esa jornada (`D-112`).
    func toResponse() -> Components.Schemas.MatchResponse {
        .init(
            id: "\(match.id)",
            competitionId: "\(match.competitionID)",
            roundId: "\(match.roundID)",
            roundNumber: roundNumber,
            matchDate: match.kickoff.date.formatted(.isoDay),
            kickoffTime: match.kickoff.time?.text,
            isKickoffConfirmed: match.isKickoffConfirmed,
            status: .init(value1: match.status.toContract()),
            venue: match.venue,
            federationMatchId: match.federationMatchID,
            home: .init(value1: home.toMatchTeam(score: match.result?.homeScore)),
            away: .init(value1: away.toMatchTeam(score: match.result?.awayScore)),
            createdAt: match.createdAt,
            updatedAt: match.updatedAt)
    }
}

extension ListMatches.Side {
    func toMatchTeam(score: Int?) -> Components.Schemas.MatchTeam {
        .init(
            value1: team.toTeamRef(),
            // Sin fila, **nada**, y la clave no viaja (`DW-21`): un envoltorio con
            // `value1` nulo sale como `{}`, que no es ni una fila ni nulo, y el
            // cliente no lo puede leer (lo enseñó la prueba del partido sin jugar).
            value2: .init(score: score, standing: standing.map {
                .init(value1: .init(
                    position: $0.position, played: $0.played, won: $0.won, drawn: $0.drawn, lost: $0.lost,
                    goalsFor: $0.goalsFor, goalsAgainst: $0.goalsAgainst, points: $0.points))
            }))
    }
}

extension Domain.MatchStatus {
    func toContract() -> Components.Schemas.MatchStatus {
        switch self {
        case .programado: .programado
        case .finalizado: .finalizado
        case .aplazado: .aplazado
        case .suspendido: .suspendido
        }
    }
}

extension Components.Schemas.MatchStatus {
    func toDomain() -> Domain.MatchStatus {
        switch self {
        case .programado: .programado
        case .finalizado: .finalizado
        case .aplazado: .aplazado
        case .suspendido: .suspendido
        }
    }
}
