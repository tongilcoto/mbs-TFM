import Fluent
import FluentPostgresDriver
import NIOConcurrencyHelpers
import SQLKit
import Vapor

/// Tenant resuelto para una petición (§6.1).
public struct Tenant: Sendable {
    public let slug: String
    public let schemaName: String

    public init(slug: String, schemaName: String) {
        self.slug = slug
        self.schemaName = schemaName
    }

    init(_ record: TenantRecord) {
        self.init(slug: record.slug, schemaName: record.schemaName)
    }
}

/// Las tres formas de enrutar a datos que el spike compara (§6.2, §6.4).
public enum TenantRoutingStrategy: String, Sendable, CaseIterable {
    /// **A** — `SET LOCAL search_path` dentro de una transacción.
    /// Postgres deshace el `SET LOCAL` al cerrar la transacción, así que la conexión
    /// vuelve limpia al pool **sin código de reseteo**.
    case setLocalInTransaction

    /// **B** — un `DatabaseID` (y por tanto un pool) por tenant, con `searchPath` fijado
    /// en la configuración: el driver emite `SET search_path` al **abrir** cada conexión.
    /// No hay transacción obligatoria y no hay nada que resetear: la conexión nunca sirve
    /// a otro tenant.
    case dedicatedPool

    /// **A′ — control negativo.** `SET search_path` a pelo sobre la conexión, tal cual lo
    /// enuncia el LLD §6.2 pero **sin el reseteo**. Existe para demostrar que el reseteo
    /// no es una precaución: es lo único que separa esto de una fuga entre tenants.
    case naiveSetSearchPath
}

public enum TenantRouting {
    /// Estrategia A. `work` recibe una `Database` **fijada a una sola conexión** dentro de
    /// una transacción con el `search_path` del tenant.
    public static func withSearchPath<T: Sendable>(
        _ schema: String,
        on database: any Database,
        _ work: @escaping @Sendable (any Database) async throws -> T
    ) async throws -> T {
        try await database.transaction { transaction in
            guard let sql = transaction as? any SQLDatabase else {
                throw TenancyError.notASQLDatabase
            }
            try await sql.raw("SET LOCAL search_path TO \(ident: schema)").run()
            return try await work(transaction)
        }
    }

    /// Estrategia A′ (control negativo). No usar fuera de los tests.
    public static func withNaiveSearchPath<T: Sendable>(
        _ schema: String,
        on database: any Database,
        _ work: @escaping @Sendable (any Database) async throws -> T
    ) async throws -> T {
        try await database.withConnection { connection in
            guard let sql = connection as? any SQLDatabase else {
                throw TenancyError.notASQLDatabase
            }
            try await sql.raw("SET search_path TO \(ident: schema)").run()
            return try await work(connection)
        }
    }
}

/// Estrategia B: registro perezoso de un pool por tenant sobre el `Databases` de la
/// aplicación (§4.7 lo contempla: *"o registra dinámicamente un `DatabaseID` por tenant"*).
///
/// `Databases.use` está protegido por lock y los drivers se crean bajo demanda, así que
/// registrar en caliente es seguro. El coste, que el spike mide, es que cada tenant
/// mantiene su propio pool.
public final class TenantPools: Sendable {
    private let databases: Databases
    private let config: SpikeConfig
    private let registered = NIOLockedValueBox<Set<String>>([])

    public init(databases: Databases, config: SpikeConfig) {
        self.databases = databases
        self.config = config
    }

    public func databaseID(for schema: String) -> DatabaseID {
        let id = DatabaseID.tenant(schema)
        registered.withLockedValue { seen in
            guard !seen.contains(schema) else { return }
            databases.use(
                .postgres(configuration: config.sqlConfiguration(searchPath: [schema])),
                as: id,
                isDefault: false
            )
            seen.insert(schema)
        }
        return id
    }

    public var registeredSchemas: Set<String> {
        registered.withLockedValue { $0 }
    }
}

// MARK: - Enganche en la aplicación y en la petición

extension Application {
    private struct TenantPoolsKey: StorageKey { typealias Value = TenantPools }
    private struct StrategyKey: StorageKey { typealias Value = TenantRoutingStrategy }
    private struct ConfigKey: StorageKey { typealias Value = SpikeConfig }

    public var tenantPools: TenantPools {
        get {
            guard let pools = storage[TenantPoolsKey.self] else {
                fatalError("TenantPools no configurado; llama a configure(_:) primero.")
            }
            return pools
        }
        set { storage[TenantPoolsKey.self] = newValue }
    }

    /// Estrategia activa. Se cambia por entorno (`TENANT_STRATEGY`) para poder correr
    /// la misma batería de tests contra A y contra B.
    public var tenantRoutingStrategy: TenantRoutingStrategy {
        get { storage[StrategyKey.self] ?? .setLocalInTransaction }
        set { storage[StrategyKey.self] = newValue }
    }

    public var spikeConfig: SpikeConfig {
        get { storage[ConfigKey.self] ?? .fromEnvironment() }
        set { storage[ConfigKey.self] = newValue }
    }
}

extension Request {
    private struct TenantKey: StorageKey { typealias Value = Tenant }

    public var tenant: Tenant? {
        get { storage[TenantKey.self] }
        set { storage[TenantKey.self] = newValue }
    }

    public func requireTenant() throws -> Tenant {
        guard let tenant else { throw TenancyError.tenantNotResolved }
        return tenant
    }

    /// Punto único por el que pasa **todo** acceso a datos de tenant.
    /// El resto del código no sabe qué estrategia hay debajo.
    public func withTenantDB<T: Sendable>(
        _ work: @escaping @Sendable (any Database) async throws -> T
    ) async throws -> T {
        let tenant = try requireTenant()
        switch application.tenantRoutingStrategy {
        case .setLocalInTransaction:
            return try await TenantRouting.withSearchPath(tenant.schemaName, on: db(.control), work)
        case .dedicatedPool:
            let id = application.tenantPools.databaseID(for: tenant.schemaName)
            return try await work(db(id))
        case .naiveSetSearchPath:
            return try await TenantRouting.withNaiveSearchPath(tenant.schemaName, on: db(.control), work)
        }
    }
}
