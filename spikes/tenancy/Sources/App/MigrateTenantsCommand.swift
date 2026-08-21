import Fluent
import SQLKit
import Vapor

/// `migrate-tenants` (§4.7) — el comando que el `migrate` de serie de Fluent no puede ser.
///
/// El de serie migra **una** base/schema. Éste recorre `public.tenants`, y para cada club
/// ejecuta el **juego completo** de migraciones contra su schema. Cada schema acaba con su
/// propia `_fluent_migrations`: el progreso se rastrea **por club**, no globalmente.
public struct MigrateTenantsCommand: AsyncCommand {
    public struct Signature: CommandSignature {
        @Option(name: "tenant", short: "t", help: "Migrar solo el club con este slug.")
        public var tenant: String?

        @Flag(name: "revert", help: "Revertir todos los lotes en lugar de aplicarlos.")
        public var revert: Bool

        public init() {}
    }

    public var help: String {
        "Aplica el juego de migraciones a cada schema de tenant registrado en public.tenants."
    }

    public init() {}

    public func run(using context: CommandContext, signature: Signature) async throws {
        let app = context.application
        let tenants = try await Self.tenants(matching: signature.tenant, on: app)

        guard !tenants.isEmpty else {
            context.console.warning("No hay tenants registrados en public.tenants.")
            return
        }

        for tenant in tenants {
            context.console.info("→ \(signature.revert ? "revirtiendo" : "migrando") \(tenant.slug) (schema \(tenant.schemaName))")
            if signature.revert {
                try await Self.revert(schema: tenant.schemaName, on: app)
            } else {
                try await Self.migrate(schema: tenant.schemaName, on: app)
            }
        }
        context.console.success("\(tenants.count) tenant(s) procesados.")
    }

    static func tenants(matching slug: String?, on app: Application) async throws -> [TenantRecord] {
        let query = TenantRecord.query(on: app.db(.control))
        if let slug { query.filter(\.$slug == slug) }
        return try await query.sort(\.$slug).all()
    }

    /// Aplica el juego completo al schema dado. Idempotente: `_fluent_migrations` del
    /// propio schema decide qué falta. Un club nuevo parte de cero y recibe todas.
    public static func migrate(schema: String, on app: Application) async throws {
        let migrator = try makeMigrator(schema: schema, on: app)
        try await migrator.setupIfNeeded().get()
        try await migrator.prepareBatch().get()
    }

    public static func revert(schema: String, on app: Application) async throws {
        let migrator = try makeMigrator(schema: schema, on: app)
        try await migrator.setupIfNeeded().get()
        try await migrator.revertAllBatches().get()
    }

    private static func makeMigrator(schema: String, on app: Application) throws -> Migrator {
        // El pool del tenant lleva `search_path` fijado al abrir la conexión, así que el
        // DDL sin cualificar (`CREATE TABLE "seasons"`) aterriza en su schema — y con él
        // la propia tabla de control `_fluent_migrations`.
        let id = app.tenantPools.databaseID(for: schema)
        let migrations = Migrations()
        migrations.add(TenantMigrations.all(), to: id)
        return Migrator(
            databases: app.databases,
            migrations: migrations,
            logger: app.logger,
            on: app.eventLoopGroup.any()
        )
    }
}

/// `provision-tenant` — alta de club del tier gestionado (§4.7): crea el schema,
/// lo registra en `public.tenants` y le pasa el migrador **completo**.
public struct ProvisionTenantCommand: AsyncCommand {
    public struct Signature: CommandSignature {
        @Argument(name: "slug", help: "Identificador público del club (subdominio / claim club_id).")
        public var slug: String

        @Option(name: "schema", short: "s", help: "Nombre del schema. Por defecto: club_<slug>.")
        public var schema: String?

        public init() {}
    }

    public var help: String { "Da de alta un club del tier gestionado: schema + registro + migraciones." }

    public init() {}

    public func run(using context: CommandContext, signature: Signature) async throws {
        let app = context.application
        let schema = signature.schema ?? "club_\(signature.slug)"
        _ = try await TenantRecord.provision(slug: signature.slug, schemaName: schema, on: app.db(.control))
        try await MigrateTenantsCommand.migrate(schema: schema, on: app)
        context.console.success("Club \(signature.slug) provisionado en el schema \(schema).")
    }
}
