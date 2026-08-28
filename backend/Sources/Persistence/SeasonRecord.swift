import Domain
public import Fluent
import Foundation

/// Modelo de persistencia de la temporada (§4.4). **No es el Dominio** y **no
/// conforma `Content`**: para cruzar HTTP están los DTOs (§5.2).
///
/// **Sin `space`**, como el resto de tablas de dominio: se emite `"seasons"` a
/// secas y la resuelve el `search_path` de la conexión (§6.2).
public final class SeasonRecord: Model, @unchecked Sendable {
    public static let schema = "seasons"

    @ID(key: .id) public var id: UUID?

    @Field(key: "label") public var label: String
    @Field(key: "federation_season_id") public var federationSeasonID: String

    /// **Derivadas de `label`** (§3.2) y por tanto **no fuente de verdad**: el
    /// Dominio las calcula, y el repositorio las escribe cada vez que guarda.
    ///
    /// Se persisten igual porque §3.2 las declara campos de la entidad y el
    /// *spec* las devuelve, y porque quien abra la tabla en TablePlus para
    /// entender qué hay dentro no puede parsear la etiqueta de cabeza. Lo que
    /// **no** se hace es leerlas al mapear a Dominio: si estas columnas y la
    /// etiqueta discreparan, manda la etiqueta.
    @Field(key: "start_date") public var startDate: Date
    @Field(key: "end_date") public var endDate: Date

    /// **Explícito, no el `@Timestamp(on: .delete)` de Fluent** (§4.4): archivar
    /// no es borrar. `Season` sí admite borrado físico, que es otra operación, y
    /// confundir las dos con el mismo *wrapper* haría que Fluent filtrara las
    /// archivadas como si estuvieran borradas.
    @OptionalField(key: "archived_at") public var archivedAt: Date?

    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    public init() {}
}

/// Segunda migración del orden de dependencia de FK de §4.6:
/// `Club → Season → OpponentClub → …`
public struct CreateSeason: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(SeasonRecord.schema)
            .id()
            .field("label", .string, .required)
            .field("federation_season_id", .string, .required)
            .field("start_date", .date, .required)
            .field("end_date", .date, .required)
            .field("archived_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            // Las dos unicidades de §3.5. **Un índice normal ya es único por
            // club**, porque la tabla vive dentro del *schema* del tenant: dos
            // clubes pueden tener a la vez la temporada 2024/25 sin colisionar.
            .unique(on: "label")
            .unique(on: "federation_season_id")
            .create()
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(SeasonRecord.schema).delete()
    }
}
