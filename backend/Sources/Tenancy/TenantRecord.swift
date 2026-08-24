public import Fluent
import Foundation

/// Registro del **plano de control** (§6.3): qué clubes hay en el tier
/// gestionado y en qué *schema* vive cada uno.
///
/// **No es la entidad de dominio `Club`** (§3.2, tabla `clubs` **dentro** de cada
/// *schema*). Son cosas distintas y confundirlas es el error que §4.7 avisa:
/// esto es infraestructura de tenancy.
public final class TenantRecord: Model, @unchecked Sendable {
    /// **El `space` es el mecanismo, no un detalle de estilo** (§4.7, §6.2).
    ///
    /// Con él, Fluent emite `"public"."tenants"` — **cualificada**—, así que la
    /// resolución del tenant **no depende del `search_path`**, que es justo lo
    /// que está a punto de fijarse. Las tablas de dominio (§3) **no** llevan
    /// `space` y las resuelve el `search_path`. Invertirlo rompe una de las dos
    /// cosas: o la resolución depende del *schema* que va a fijar, o el DDL de
    /// dominio aterriza en `public`.
    public static let space: String? = "public"
    public static let schema = "tenants"

    @ID(key: .id) public var id: UUID?

    /// Slug del club. Es el que viaja en el subdominio (§6.1).
    @Field(key: "slug") public var slug: String

    /// *Schema* de Postgres donde vive este club.
    @Field(key: "schema_name") public var schemaName: String

    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?

    public init() {}

    public init(id: UUID? = nil, slug: String, schemaName: String) {
        self.id = id
        self.slug = slug
        self.schemaName = schemaName
    }
}

/// Migración del plano de control. Se aplica **una vez, contra `public`**, y
/// **no** forma parte del juego que recorre los tenants (§4.7).
public struct CreateTenants: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(TenantRecord.schema)
            .id()
            .field("slug", .string, .required)
            .field("schema_name", .string, .required)
            .field("created_at", .datetime)
            .unique(on: "slug")
            .unique(on: "schema_name")
            .create()
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(TenantRecord.schema).delete()
    }
}
