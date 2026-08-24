import Fluent
import SQLKit
import Tenancy
public import Vapor

/// `migrate-tenants` (§4.7) — lo que el `migrate` de serie de Fluent no puede ser.
///
/// El de serie migra **una** base o *schema*. Éste recorre `public.tenants` y
/// aplica a cada club el juego **completo**. Cada *schema* acaba con su propia
/// `_fluent_migrations`, así que el progreso se rastrea **por club**: revertir
/// uno no toca a los demás, y un alta nueva recibe todas las migraciones, no
/// solo la última pendiente. Comprobado en el spike (H1).
///
/// - Important: **Va por la conexión directa, nunca por el *pooler*** (§6.4). Se
///   apoya en un `SET` de sesión, que en modo transacción deja de significar lo
///   que parece. El precio de que falle no es leer mal: es crear la tabla en el
///   *schema* equivocado, y eso no se deshace reintentando.
public struct MigrateTenantsCommand: AsyncCommand {
    public struct Signature: CommandSignature {
        @Option(name: "tenant", short: "t", help: "Migrar solo el club con este slug.")
        public var tenant: String?

        @Flag(name: "revert", help: "Revertir todos los lotes en lugar de aplicarlos.")
        public var revert: Bool

        public init() {}
    }

    public var help: String {
        "Aplica el juego de migraciones a cada schema de tenant de public.tenants."
    }

    public init() {}

    public func run(using context: CommandContext, signature: Signature) async throws {
        let app = context.application
        let query = TenantRecord.query(on: app.db(.control))
        if let slug = signature.tenant { query.filter(\.$slug == slug) }
        let tenants = try await query.sort(\.$slug).all()

        guard !tenants.isEmpty else {
            context.console.warning("No hay tenants registrados en public.tenants.")
            return
        }

        for tenant in tenants {
            let verb = signature.revert ? "revirtiendo" : "migrando"
            context.console.info("→ \(verb) \(tenant.slug) (schema \(tenant.schemaName))")
            if signature.revert {
                try await Self.revert(schema: tenant.schemaName, on: app)
            } else {
                try await Self.migrate(schema: tenant.schemaName, on: app)
            }
        }
        context.console.success("\(tenants.count) tenant(s) procesados.")
    }

    /// Idempotente: la `_fluent_migrations` del propio *schema* decide qué falta.
    public static func migrate(schema: String, on app: Application) async throws {
        let migrator = makeMigrator(schema: schema, on: app)
        try await migrator.setupIfNeeded().get()
        try await migrator.prepareBatch().get()
    }

    public static func revert(schema: String, on app: Application) async throws {
        let migrator = makeMigrator(schema: schema, on: app)
        try await migrator.setupIfNeeded().get()
        try await migrator.revertAllBatches().get()
    }

    private static func makeMigrator(schema: String, on app: Application) -> Migrator {
        // El *pool* del tenant lleva `search_path` fijado al abrir la conexión,
        // así que el DDL sin cualificar (`CREATE TABLE "clubs"`) aterriza en su
        // *schema* — y con él la propia `_fluent_migrations`.
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

/// `provision-tenant` — alta de club del tier gestionado (§6.3).
///
/// **Es un comando administrativo, no un endpoint**: por eso `/club` no tiene
/// `POST` ni `DELETE` (D-23). Crea el *schema*, lo registra y le pasa el
/// migrador completo, porque parte de cero.
public struct ProvisionTenantCommand: AsyncCommand {
    public struct Signature: CommandSignature {
        @Argument(name: "slug", help: "Identificador público del club (subdominio / claim club_id).")
        public var slug: String

        @Option(name: "schema", short: "s", help: "Nombre del schema. Por defecto: club_<slug>.")
        public var schema: String?

        public init() {}
    }

    public var help: String {
        "Da de alta un club del tier gestionado: schema + registro + migraciones."
    }

    public init() {}

    public func run(using context: CommandContext, signature: Signature) async throws {
        let app = context.application
        let schema = signature.schema ?? "club_\(signature.slug)"
        try await Self.provision(slug: signature.slug, schemaName: schema, on: app)
        context.console.success("Club \(signature.slug) provisionado en el schema \(schema).")
    }

    public static func provision(slug: String, schemaName: String, on app: Application) async throws {
        guard let sql = app.db(.control) as? any SQLDatabase else {
            throw TenancyError.notASQLDatabase
        }
        try await sql.raw("CREATE SCHEMA IF NOT EXISTS \(ident: schemaName)").run()

        let existing = try await TenantRecord.query(on: app.db(.control))
            .filter(\.$slug == slug)
            .first()
        if existing == nil {
            try await TenantRecord(slug: slug, schemaName: schemaName).save(on: app.db(.control))
        }
        try await MigrateTenantsCommand.migrate(schema: schemaName, on: app)
    }
}
