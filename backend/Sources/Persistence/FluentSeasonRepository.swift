import Fluent
import Foundation
public import Application
public import Domain

/// Adaptador secundario: implementa `SeasonRepository` (§4.3).
///
/// Recibe la `Database` **ya dentro del ámbito de tenant** (§6.2), así que aquí
/// no hay ni rastro de *schemas*.
public struct FluentSeasonRepository: SeasonRepository {
    private let database: any Database

    public init(database: any Database) {
        self.database = database
    }

    public func find(_ id: SeasonID) async throws -> Season? {
        try await SeasonRecord.find(id.raw, on: database)?.toDomain()
    }

    public func findByFederationID(_ federationSeasonID: String) async throws -> Season? {
        try await SeasonRecord.query(on: database)
            .filter(\.$federationSeasonID == federationSeasonID)
            .first()?
            .toDomain()
    }

    public func list(includingArchived: Bool) async throws -> [Season] {
        let query = SeasonRecord.query(on: database)
        if !includingArchived {
            // El *scope* por defecto de §3.5. No es el `deleted_at` de Fluent:
            // `archived_at` es un campo normal, así que el filtro es explícito.
            query.filter(\.$archivedAt == .null)
        }
        // Orden estable y con sentido de negocio: la más reciente primero.
        return try await query.sort(\.$endDate, .descending).all().map { try $0.toDomain() }
    }

    public func save(_ season: Season) async throws {
        // *Upsert* de verdad, a diferencia de `ClubRepository.save`: aquí el alta
        // es una operación normal (`D-16`), no provisión.
        if let existing = try await SeasonRecord.find(season.id.raw, on: database) {
            existing.apply(season)
            try await existing.update(on: database)
        } else {
            let record = SeasonRecord()
            record.id = season.id.raw
            record.apply(season)
            try await record.create(on: database)
        }
    }
}

extension SeasonRecord {
    /// Mapeo `Entidad → Record`, que es trabajo del repositorio (§4.4).
    ///
    /// `start_date`/`end_date` se **reescriben desde la etiqueta** en cada
    /// guardado: son derivadas (§3.2) y no pueden quedarse atrás si la etiqueta
    /// cambia.
    func apply(_ season: Season) {
        label = season.label.value
        federationSeasonID = season.federationSeasonID
        startDate = season.startDate
        endDate = season.endDate
        archivedAt = season.archivedAt
    }

    /// Mapeo `Record → Entidad`.
    ///
    /// **No lee `start_date` ni `end_date`**: las deriva el Dominio de la
    /// etiqueta. Si las columnas discreparan —alguien escribiendo SQL a mano—,
    /// manda la etiqueta, que es la que lleva el `UNIQUE` y la que ve el usuario.
    func toDomain() throws -> Season {
        guard let createdAt, let updatedAt else {
            throw PersistenceError.missingTimestamp(
                table: Self.schema, id: try requireID().uuidString)
        }
        return try Season(
            id: SeasonID(raw: try requireID()),
            label: SeasonLabel(label),
            federationSeasonID: federationSeasonID,
            archivedAt: archivedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
