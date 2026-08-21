import Fluent
import Foundation
import SQLKit

/// Registro de tenants del **plano de control** (LLD §4.7, §6).
///
/// Vive en `public`, **fuera** de todo schema de tenant, y no es la entidad de dominio
/// `Club` (§3.2) — que vive *dentro* de cada schema. `space = "public"` hace que Fluent
/// cualifique la tabla como `"public"."tenants"`: así esta consulta **no depende del
/// `search_path`**, que es justo lo que se quiere de una tabla de infraestructura.
public final class TenantRecord: Model, @unchecked Sendable {
    public static let schema = "tenants"
    public static let space: String? = "public"

    @ID(key: .id)
    public var id: UUID?

    /// Identificador público del club: subdominio o claim `club_id` del JWT (§6.1).
    @Field(key: "slug")
    public var slug: String

    /// Nombre del schema Postgres del club.
    @Field(key: "schema_name")
    public var schemaName: String

    @Timestamp(key: "created_at", on: .create)
    public var createdAt: Date?

    public init() {}

    public init(id: UUID? = nil, slug: String, schemaName: String) {
        self.id = id
        self.slug = slug
        self.schemaName = schemaName
    }
}

/// Migración del plano de control. Se aplica **una sola vez**, contra `public`,
/// y no forma parte del juego de migraciones que recorre los tenants (§4.7).
public struct CreateTenants: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(TenantRecord.schema, space: TenantRecord.space)
            .id()
            .field("slug", .string, .required)
            .field("schema_name", .string, .required)
            .field("created_at", .datetime)
            .unique(on: "slug")
            .unique(on: "schema_name")
            .create()
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(TenantRecord.schema, space: TenantRecord.space).delete()
    }
}

extension TenantRecord {
    /// Resolución de tenant (§6.1): slug → schema.
    static func find(slug: String, on database: any Database) async throws -> TenantRecord? {
        try await TenantRecord.query(on: database).filter(\.$slug == slug).first()
    }

    /// Alta de club del tier gestionado (§4.7): crear el schema y registrarlo.
    /// El migrador completo se ejecuta aparte, con `migrate-tenants`.
    static func provision(slug: String, schemaName: String, on database: any Database) async throws -> TenantRecord {
        guard let sql = database as? any SQLDatabase else {
            throw TenancyError.notASQLDatabase
        }
        try await sql.raw("CREATE SCHEMA IF NOT EXISTS \(ident: schemaName)").run()
        if let existing = try await find(slug: slug, on: database) { return existing }
        let record = TenantRecord(slug: slug, schemaName: schemaName)
        try await record.create(on: database)
        return record
    }
}

public enum TenancyError: Error, CustomStringConvertible {
    case notASQLDatabase
    case tenantNotResolved
    case unknownTenant(String)

    public var description: String {
        switch self {
        case .notASQLDatabase:
            "La base de datos no expone SQLDatabase; el enrutado por schema necesita SQL crudo."
        case .tenantNotResolved:
            "No hay tenant en la petición: falta el middleware de resolución (§6.1)."
        case .unknownTenant(let slug):
            "Tenant desconocido: \(slug)"
        }
    }
}
