import Domain
public import Fluent
import Foundation
import SQLKit

/// Modelo de persistencia de la temporada (§4.4). **No es el Dominio** y **no
/// conforma `Content`**: para cruzar HTTP están los DTOs (§5.2).
///
/// **Sin `space`**, como el resto de tablas de dominio: se emite `"seasons"` a
/// secas y la resuelve el `search_path` de la conexión (§6.2).
public final class SeasonRecord: Model, @unchecked Sendable {
    public static let schema = "seasons"

    @ID(key: .id) public var id: UUID?

    @Field(key: "label") public var label: String
    /// **Anulable desde `D-106`** (migración `AllowSeasonWithoutFederationCode`):
    /// la temporada nace en la web sin código, y el primer enganche se lo pone.
    @OptionalField(key: "federation_season_id") public var federationSeasonID: String?

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

/// **`D-106`: la temporada puede nacer sin código de la federación.** El club la
/// crea en julio, desde la web y solo con su etiqueta, y el primer enganche le
/// pone el código. Quita el «obligatorio» de `federation_season_id`; su `UNIQUE`
/// se queda, y en Postgres no cuenta los vacíos, así que caben varias sin código.
///
/// **El revert se para si alguna temporada no tiene código**, en vez de inventarle
/// uno: volver a exigirlo con filas vacías fallaría a medias, y rellenarlas sería
/// llamar a la federación con un número que nadie ha visto.
public struct AllowSeasonWithoutFederationCode: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        let sql = try Self.sql(database)
        try await sql.raw("""
            ALTER TABLE \(ident: SeasonRecord.schema)
              ALTER COLUMN federation_season_id DROP NOT NULL
            """).run()
    }

    public func revert(on database: any Database) async throws {
        let sql = try Self.sql(database)
        let missing = try await sql.raw("""
            SELECT count(*) AS n FROM \(ident: SeasonRecord.schema)
             WHERE federation_season_id IS NULL
            """).first(decodingColumn: "n", as: Int.self) ?? 0
        guard missing == 0 else {
            throw PersistenceError.migrationWouldLoseData(
                migration: "AllowSeasonWithoutFederationCode",
                reason: "\(missing) temporada(s) sin código de la federación: volver a "
                    + "exigirlo no tiene con qué rellenarlas (D-106)")
        }
        try await sql.raw("""
            ALTER TABLE \(ident: SeasonRecord.schema)
              ALTER COLUMN federation_season_id SET NOT NULL
            """).run()
    }

    private static func sql(_ database: any Database) throws -> any SQLDatabase {
        guard let sql = database as? any SQLDatabase else {
            throw PersistenceError.schemaHelperNeedsSQL(
                helper: "AllowSeasonWithoutFederationCode", object: SeasonRecord.schema)
        }
        return sql
    }
}
