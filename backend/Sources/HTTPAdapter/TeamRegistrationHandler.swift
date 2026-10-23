public import APIContract
import Application
import Domain
import Foundation

/// `GET /v1/seasons/{seasonId}/registrations` (`D-102`, Plan R1): los equipos del
/// club en una temporada, cada uno con sus competiciones.
extension APIHandler {
    public func listSeasonRegistrations(_ input: Operations.listSeasonRegistrations.Input) async throws
        -> Operations.listSeasonRegistrations.Output
    {
        let actor = try actors.currentActor()
        let seasonID: SeasonID
        do {
            seasonID = SeasonID(raw: try Self.uuid(input.path.seasonId, field: "seasonId"))
        } catch let error as InvalidUUID {
            return .badRequest(Self.invalidUUID(error))
        }
        // La temporada que no existe la lanza el caso de uso y la traduce el
        // middleware (404 `SEASON_NOT_FOUND`), como manda H-63.
        let result = try await unitOfWork.withRepositories(actor: actor) { repositories in
            try await ListSeasonRegistrations(
                clubs: repositories.clubs, seasons: repositories.seasons,
                teams: repositories.teams, registrations: repositories.teamRegistrations
            ).execute(actor: actor, seasonID: seasonID)
        }
        return .ok(.init(body: .json(result.entries.map { $0.toResponse(club: result.club) })))
    }
}

extension SeasonRegistration {
    /// Mapeo `Caso de uso → DTO` (§2.2). `team` es la respuesta de un equipo, que
    /// **no cambia nunca de forma** (`D-102`): lo de la temporada viaja fuera.
    func toResponse(club: Domain.Club) -> Components.Schemas.TeamRegistrationResponse {
        .init(
            team: team.toResponse(club: club),
            seasonId: "\(seasonID)",
            competitions: competitions.map {
                .init(competitionId: "\($0.competitionID)", federationTeamId: $0.federationTeamID)
            })
    }
}

extension Domain.Team {
    /// Mapeo `Entidad → DTO` de un equipo **propio**, que es lo único que se
    /// inscribe (`D-68`). Los derivados se componen aquí (§3.6):
    ///
    /// - `clubName` es el **nombre corto** del club, el de las cabeceras;
    /// - `displayName`, `clubName` + categoría + letra («Celtic Castilla Cadete B»);
    /// - `crestUrl`, nulo hasta que exista el adaptador de Storage, como el del club.
    ///
    /// `federationTeamId` es nulo en un propio (`D-101`): su código va en la
    /// inscripción de cada competición.
    func toResponse(club: Domain.Club) -> Components.Schemas.TeamResponse {
        .init(
            id: "\(id)",
            category: category.toContract(),
            letter: letter,
            gender: .init(value1: gender.toContract()),
            modality: .init(value1: modality.toContract()),
            opponentClubId: nil,
            // Un propio no tiene temporada (`D-104`): la suya es la de la inscripción.
            seasonId: seasonID.map { "\($0)" },
            federationTeamId: federationTeamID,
            isOwn: isOwn,
            clubName: club.shortName,
            displayName: [club.shortName, category.displayLabel, letter]
                .compactMap { $0 }.joined(separator: " "),
            crestUrl: nil,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
