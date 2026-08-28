import Fluent
import Foundation
public import Application
public import Domain

/// Adaptador secundario: implementa `CompetitionRepository` (§4.3).
public struct FluentCompetitionRepository: CompetitionRepository {
    private let database: any Database

    public init(database: any Database) {
        self.database = database
    }

    public func find(_ id: CompetitionID) async throws -> Competition? {
        try await CompetitionRecord.find(id.raw, on: database)?.toDomain()
    }

    public func findByFederationGroup(
        seasonID: SeasonID, federationGroupID: String
    ) async throws -> Competition? {
        // Exactamente la clave única de §3.5, que es también el índice que sirve
        // esta consulta.
        try await CompetitionRecord.query(on: database)
            .filter(\.$season.$id == seasonID.raw)
            .filter(\.$federationGroupID == federationGroupID)
            .first()?
            .toDomain()
    }

    public func list(seasonID: SeasonID) async throws -> [Competition] {
        try await CompetitionRecord.query(on: database)
            .filter(\.$season.$id == seasonID.raw)
            .sort(\.$ageCategory)
            .sort(\.$groupLabel)
            .all()
            .map { try $0.toDomain() }
    }

    public func save(_ competition: Competition) async throws {
        if let existing = try await CompetitionRecord.find(competition.id.raw, on: database) {
            existing.apply(competition)
            try await existing.update(on: database)
        } else {
            let record = CompetitionRecord()
            record.id = competition.id.raw
            record.apply(competition)
            try await record.create(on: database)
        }
    }
}

extension CompetitionRecord {
    /// Mapeo `Entidad → Record` (§4.4). Los enumerados bajan a su *raw value*;
    /// el `CHECK` de la migración garantiza que la columna no salga del dominio.
    func apply(_ competition: Competition) {
        $season.id = competition.seasonID.raw
        modality = competition.modality.rawValue
        gender = competition.gender.rawValue
        ageCategory = competition.ageCategory.rawValue
        federationCompetitionID = competition.federationCompetitionID
        federationGroupID = competition.federationGroupID
        divisionLabel = competition.divisionLabel
        groupLabel = competition.groupLabel
        federationName = competition.federationName
        lastSyncedAt = competition.lastSyncedAt
    }

    /// Mapeo `Record → Entidad`. Los tres enumerados se reconstruyen desde el
    /// *raw value*; que fallen es **corrupción**, no un caso de negocio:
    /// significaría que alguien escribió en la tabla saltándose el `CHECK`.
    func toDomain() throws -> Competition {
        guard let modality = Modality(rawValue: modality) else {
            throw PersistenceError.corruptEnumeration(
                table: Self.schema, column: "modality", value: self.modality)
        }
        guard let gender = Gender(rawValue: gender) else {
            throw PersistenceError.corruptEnumeration(
                table: Self.schema, column: "gender", value: self.gender)
        }
        guard let ageCategory = TeamCategory(rawValue: ageCategory) else {
            throw PersistenceError.corruptEnumeration(
                table: Self.schema, column: "age_category", value: self.ageCategory)
        }
        guard let createdAt, let updatedAt else {
            throw PersistenceError.missingTimestamp(
                table: Self.schema, id: try requireID().uuidString)
        }
        return try Competition(
            id: CompetitionID(raw: try requireID()),
            seasonID: SeasonID(raw: $season.id),
            modality: modality,
            gender: gender,
            federationCompetitionID: federationCompetitionID,
            federationGroupID: federationGroupID,
            ageCategory: ageCategory,
            divisionLabel: divisionLabel,
            groupLabel: groupLabel,
            federationName: federationName,
            lastSyncedAt: lastSyncedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
