import Fluent
import Foundation

/// `Season` (§3.2) — la entidad más simple del modelo: sin FKs y raíz del árbol de ingesta.
/// Es la única entidad del spike; lo que se prueba aquí no es el modelo, es el enrutado.
///
/// **Sin `space`, a diferencia de `TenantRecord`**: la tabla se emite sin cualificar
/// (`"seasons"`), así que la resuelve el `search_path` de la conexión. Ése es el mecanismo
/// que el spike pone a prueba (§6.2).
public final class SeasonRecord: Model, @unchecked Sendable {
    public static let schema = "seasons"

    @ID(key: .id)
    public var id: UUID?

    /// "2024/25" — único por tenant (§3.5).
    @Field(key: "label")
    public var label: String

    /// Secuencial de la federación (`temporada=21`), tecleado por el administrador (§3.2).
    @Field(key: "federation_season_id")
    public var federationSeasonID: Int

    /// Derivadas de `label` (01/07/AAAA → 30/06/AABB), no overridables (§3.2).
    @Field(key: "start_date")
    public var startDate: Date

    @Field(key: "end_date")
    public var endDate: Date

    /// Archivado reversible, no borrado (§3.5).
    @OptionalField(key: "archived_at")
    public var archivedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    public var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    public var updatedAt: Date?

    public init() {}

    public init(id: UUID? = nil, label: String, federationSeasonID: Int) {
        self.id = id
        self.label = label
        self.federationSeasonID = federationSeasonID
        let (start, end) = Self.dates(from: label)
        self.startDate = start
        self.endDate = end
    }

    /// 01/07/AAAA → 30/06/AABB (§3.2). Suficiente para el spike; en el backend real
    /// esto es un Value Object `SeasonLabel` del Dominio (§4.1).
    static func dates(from label: String) -> (Date, Date) {
        let startYear = Int(label.prefix(4)) ?? 2000
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: startYear, month: 7, day: 1))!
        let end = calendar.date(from: DateComponents(year: startYear + 1, month: 6, day: 30))!
        return (start, end)
    }
}

/// Migración de `Season` (§4.6): `AsyncMigration` por entidad, `revert` simétrico.
/// Las dos unicidades de §3.5 (`label`, `federation_season_id`) van aquí porque son
/// justamente lo que hay que ver **repetido e independiente en cada schema**.
public struct CreateSeason: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(SeasonRecord.schema)
            .id()
            .field("label", .string, .required)
            .field("federation_season_id", .int, .required)
            .field("start_date", .date, .required)
            .field("end_date", .date, .required)
            .field("archived_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "label")
            .unique(on: "federation_season_id")
            .create()
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(SeasonRecord.schema).delete()
    }
}

/// El juego de migraciones que recorre **todos** los tenants (§4.7).
/// En el backend real, aquí van las 15 en orden de dependencia de FK.
public enum TenantMigrations {
    public static func all() -> [any Migration] {
        [CreateSeason()]
    }
}
