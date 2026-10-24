public import APIContract
import Application
import Domain
import Foundation

/// `GET /v1/competitions` (§5.1, Plan R1): las competiciones del club, con sus
/// cuatro filtros, para la portada del backoffice.
extension APIHandler {
    public func listCompetitions(_ input: Operations.listCompetitions.Input) async throws
        -> Operations.listCompetitions.Output
    {
        let actor = try actors.currentActor()
        let query = input.query
        let filter: CompetitionFilter
        do {
            filter = CompetitionFilter(
                seasonID: try query.seasonId.map { SeasonID(raw: try Self.uuid($0, field: "seasonId")) },
                modality: query.modality?.toDomain(),
                ageCategory: query.ageCategory?.toDomain(),
                gender: query.gender?.toDomain())
        } catch let error as InvalidUUID {
            return .badRequest(Self.invalidUUID(error))
        }
        let clock = self.clock
        let listings = try await unitOfWork.withRepositories(actor: actor) { repositories in
            try await ListCompetitions(
                competitions: repositories.competitions,
                ingestionRuns: repositories.ingestionRuns,
                clock: clock
            ).execute(filter)
        }
        return .ok(.init(body: .json(listings.map { $0.toResponse() })))
    }
}

extension CompetitionListing {
    /// Mapeo `Caso de uso → DTO` (§2.2): la competición, con los tres campos que
    /// se derivan al leerla (`D-89`). `previousIngestionHealth` solo viene con
    /// `pending`, y eso ya lo garantiza el Dominio.
    func toResponse() -> Components.Schemas.CompetitionResponse {
        var response = competition.toResponse()
        response.lastIngestionAt = lastIngestionAt
        response.ingestionHealth = ingestion.health.toContract()
        response.previousIngestionHealth = ingestion.previous.map { .init(value1: $0.toContract()) }
        return response
    }
}

extension Domain.Competition {
    /// **Derivado en lectura** (§5.2): `ageCategory · divisionLabel · groupLabel`, con el nombre de la categoría del
    /// catálogo (`D-109`). No hay columna detrás: la federación publica un nombre propio, pero llega truncado a 40
    /// caracteres y con formato inestable ([Anexo RFFM §F.11]), así que se compone de piezas nuestras.
    var displayName: String {
        "\(ageCategory.toContract().displayName) · \(divisionLabel) · \(groupLabel)"
    }

    /// Mapeo `Entidad → DTO` (§2.2), con lo que es de la competición sola.
    func toResponse() -> Components.Schemas.CompetitionResponse {
        .init(
            id: "\(id)",
            seasonId: "\(seasonID)",
            modality: modality.toContract(),
            gender: gender.toContract(),
            ageCategory: ageCategory.toContract(),
            divisionLabel: divisionLabel,
            groupLabel: groupLabel,
            federationCompetitionId: federationCompetitionID,
            federationGroupId: federationGroupID,
            displayName: displayName,
            lastSyncedAt: lastSyncedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension Domain.IngestionHealth {
    /// `switch` exhaustivo por lo mismo que sus hermanas (`D-61`); que cada valor
    /// vaya a su gemelo lo exige `ContractEnumTests`.
    func toContract() -> Components.Schemas.IngestionHealth {
        switch self {
        case .ok: .ok
        case .failing: .failing
        case .stale: .stale
        case .never: .never
        case .pending: .pending
        }
    }
}

extension Components.Schemas.Modality {
    /// Del contrato al Dominio, para el filtro `modality` (R1.7). `switch`
    /// exhaustivo por lo mismo que sus hermanas (`D-61`); que cada valor vaya a
    /// su gemelo lo exige `ContractEnumTests`.
    func toDomain() -> Domain.Modality {
        switch self {
        case .futbol_11: .futbol11
        case .futbol_7: .futbol7
        case .futbol_5: .futbol5
        case .futbol_sala: .futbolSala
        case .futbol_playa: .futbolPlaya
        }
    }
}

extension Components.Schemas.TeamCategory {
    /// Del contrato al Dominio, para el filtro `ageCategory` (R1.7).
    func toDomain() -> Domain.TeamCategory {
        switch self {
        case .prebenjamin: .prebenjamin
        case .benjamin: .benjamin
        case .alevin: .alevin
        case .infantil: .infantil
        case .cadete: .cadete
        case .juvenil: .juvenil
        case .senior: .senior
        }
    }
}
