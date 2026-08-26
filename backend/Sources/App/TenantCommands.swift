import Domain
import Fluent
import Persistence
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
/// `POST` ni `DELETE` (D-23). Y por eso mismo **crea también la fila de `clubs`**:
/// si el alta del club es provisión, la provisión tiene que dejarlo dado de alta.
/// Dejar el *schema* con las tablas vacías produce un tenant a medias, cuyo
/// síntoma es un `tenantNotProvisioned` en la primera lectura.
///
/// Los tres pasos de §6.3, en orden: crear el *schema*, registrar el club en el
/// plano de control y ejecutar el juego **completo** de migraciones. Más el
/// cuarto que faltaba: sembrar la raíz del tenant.
public struct ProvisionTenantCommand: AsyncCommand {
    public struct Signature: CommandSignature {
        @Argument(name: "slug", help: "Identificador público del club (subdominio / claim club_id).")
        public var slug: String

        @Option(name: "federation", short: "f",
                help: "Federación del club. Valores: \(FederationCode.allCases.map(\.rawValue).joined(separator: ", ")).")
        public var federation: String?

        // **Sin opción corta a propósito.** `-n` lo reserva ConsoleKit para el
        // "no" de las confirmaciones, y declararlo aquí no da un error: sale en
        // el `--help` como si funcionase y luego el valor cae en
        // `.unknownInput`. Anunciar una opción que no existe es peor que no
        // tenerla. `-f` y `-s` sí funcionan.
        @Option(name: "name", help: "Nombre oficial. Por defecto: el slug.")
        public var name: String?

        @Option(name: "short-name", help: "Nombre corto. Por defecto: el nombre.")
        public var shortName: String?

        @Option(name: "schema", short: "s", help: "Nombre del schema. Por defecto: club_<slug>.")
        public var schema: String?

        public init() {}
    }

    public var help: String {
        "Da de alta un club del tier gestionado: schema + registro + migraciones + la fila del club."
    }

    public init() {}

    public func run(using context: CommandContext, signature: Signature) async throws {
        let app = context.application
        let schema = signature.schema ?? "club_\(signature.slug)"

        // La federación **no tiene valor por defecto honesto**: determina a qué
        // API se sincroniza el tenant entero (§3.6) y elegirla por él sería
        // inventarse un dato. Se valida contra el catálogo (D-17), que es el
        // único sitio donde vive la lista.
        guard let raw = signature.federation else {
            throw ProvisionError.missingFederation
        }
        guard let federation = FederationCode(rawValue: raw) else {
            throw ProvisionError.unknownFederation(raw)
        }

        let name = signature.name ?? signature.slug
        try await Self.provision(
            slug: signature.slug,
            schemaName: schema,
            name: name,
            shortName: signature.shortName ?? name,
            federation: federation,
            on: app
        )
        context.console.success("""
            Club \(signature.slug) provisionado en el schema \(schema).
              federación: \(federation.rawValue)
              prueba:     curl http://\(signature.slug).localhost:8080/v1/club
            """)
    }

    /// Idempotente en los cuatro pasos: repetirla sobre un club existente no
    /// duplica nada. Es lo que permite usarla también desde los tests.
    public static func provision(
        slug: String,
        schemaName: String,
        name: String,
        shortName: String,
        federation: FederationCode,
        on app: Application
    ) async throws {
        guard let sql = app.db(.control) as? any SQLDatabase else {
            throw TenancyError.notASQLDatabase
        }
        // 1 · el schema
        try await sql.raw("CREATE SCHEMA IF NOT EXISTS \(ident: schemaName)").run()

        // 2 · el registro en el plano de control
        let existing = try await TenantRecord.query(on: app.db(.control))
            .filter(\.$slug == slug)
            .first()
        if existing == nil {
            try await TenantRecord(slug: slug, schemaName: schemaName).save(on: app.db(.control))
        }

        // 3 · el juego completo de migraciones contra su schema
        try await MigrateTenantsCommand.migrate(schema: schemaName, on: app)

        // 4 · la raíz del tenant. `Club` es *singleton* (§4.2): si ya hay fila,
        //     no se toca — su contenido se edita por `PATCH /club`, no repitiendo
        //     la provisión.
        try await TenantRouting.withSearchPath(schemaName, on: app.db(.control)) { database in
            let alreadySeeded = try await ClubRecord.query(on: database).first() != nil
            guard !alreadySeeded else { return }
            let record = ClubRecord()
            record.name = name
            record.shortName = shortName
            record.slug = slug
            record.federation = federation.rawValue
            try await record.save(on: database)
        }
    }

    enum ProvisionError: Error, CustomStringConvertible {
        case missingFederation
        case unknownFederation(String)

        var description: String {
            let valid = FederationCode.allCases.map(\.rawValue).joined(separator: ", ")
            switch self {
            case .missingFederation:
                return "Falta --federation. Valores válidos: \(valid)."
            case .unknownFederation(let raw):
                return "Federación desconocida '\(raw)'. Valores válidos: \(valid)."
            }
        }
    }
}
