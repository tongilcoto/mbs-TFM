public import Fluent
import Foundation

/// Modelo de persistencia del club (§4.4). **No es el Dominio** y **no conforma
/// `Content`**: un modelo de persistencia no cruza la frontera HTTP, para eso
/// están los DTOs (§5.2). El repositorio traduce entre los dos.
///
/// **Sin `space`**, y es deliberado: se emite `"clubs"` a secas y la resuelve el
/// `search_path` de la conexión (§6.2). El contraste con `TenantRecord` —que sí
/// lo lleva— es el mecanismo de la multi-tenancy, no un detalle de estilo.
public final class ClubRecord: Model, @unchecked Sendable {
    public static let schema = "clubs"

    @ID(key: .id) public var id: UUID?

    @Field(key: "name") public var name: String
    @Field(key: "short_name") public var shortName: String
    @Field(key: "slug") public var slug: String

    /// Clave del objeto en Storage, no una URL (D-19).
    @OptionalField(key: "crest_key") public var crestKey: String?

    /// Enumerado como `text` + `CHECK`, **no `ENUM` nativo** (D-02): un tipo
    /// `ENUM` vive dentro de un *schema*, así que añadir un valor obligaría a
    /// alterarlo en **cada** *schema* de tenant. El `enum` de verdad vive en el
    /// Dominio y es la fuente de verdad; aquí se guarda su *raw value*.
    @Field(key: "federation") public var federation: String

    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    public init() {}
}

/// Primera migración del orden de dependencia de FK de §4.6:
/// `Club → Season → OpponentClub → Team → …`
public struct CreateClub: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(ClubRecord.schema)
            .id()
            .field("name", .string, .required)
            .field("short_name", .string, .required)
            .field("slug", .string, .required)
            .field("crest_key", .string)
            .field("federation", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "slug")
            .create()

        // El `CHECK` del enumerado va junto a la columna (§4.6). Es lo que
        // permite que el repositorio haga `FederationCode(rawValue:)!` al mapear
        // sin mentir: el dominio de la columna está garantizado por la BD.
        try await database.checkConstraint(
            table: ClubRecord.schema,
            name: "chk_clubs_federation",
            expression: "federation IN ('rffm', 'fcf')"
        )
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(ClubRecord.schema).delete()
    }
}
