public import APIContract
import Application
import Domain
import Foundation

/// `GET /v1/seasons` (§5.1, Plan R1): las temporadas del club, para el selector
/// de temporada de la portada del backoffice.
extension APIHandler {
    public func listSeasons(_ input: Operations.listSeasons.Input) async throws
        -> Operations.listSeasons.Output
    {
        let actor = try actors.currentActor()
        let clock = self.clock
        // El valor por omisión del *spec* (`default: false`) se aplica aquí: el
        // tipo generado lo deja en `nil` cuando no viene.
        let includingArchived = input.query.includeArchived ?? false
        let listing = try await unitOfWork.withRepositories(actor: actor) { repositories in
            try await ListSeasons(seasons: repositories.seasons, clock: clock)
                .execute(includingArchived: includingArchived)
        }
        return .ok(.init(body: .json(listing.seasons.map {
            $0.toResponse(isCurrent: $0.id == listing.currentID)
        })))
    }
}

extension Domain.Season {
    /// Mapeo `Entidad → DTO` (§2.2). `isCurrent` llega de fuera porque no es de
    /// la temporada sola: lo decide el caso de uso con el reloj (§3.2).
    func toResponse(isCurrent: Bool) -> Components.Schemas.SeasonResponse {
        .init(
            id: "\(id)",
            label: label.value,
            federationSeasonId: federationSeasonID,
            startDate: startDate.formatted(Self.isoDay),
            endDate: endDate.formatted(Self.isoDay),
            isCurrent: isCurrent,
            archivedAt: archivedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Días sin hora (`format: date`), en UTC, que es como los construye
    /// `SeasonLabel`: con otro huso, el 1 de julio saldría 30 de junio.
    private static let isoDay = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()
}
