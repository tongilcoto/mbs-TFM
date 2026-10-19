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
        let competitions = try await unitOfWork.withRepositories(actor: actor) { repositories in
            try await ListCompetitions(competitions: repositories.competitions).execute(filter)
        }
        return .ok(.init(body: .json(competitions.map { $0.toResponse() })))
    }
}

extension Domain.Competition {
    /// Mapeo `Entidad → DTO` (§2.2). **Sin el estado de la ingesta todavía**
    /// (`lastIngestionAt`, `ingestionHealth`, `previousIngestionHealth`): son
    /// opcionales en el catálogo, y llegan con R1.8.
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
