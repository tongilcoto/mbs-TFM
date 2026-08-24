import APIContract
import Application
import Fluent
import FluentPostgresDriver
import HTTPAdapter
import OpenAPIVapor
import Persistence
import Tenancy
public import Vapor

extension Application {
    private struct TenantPoolsKey: StorageKey { typealias Value = TenantPools }

    public var tenantPools: TenantPools {
        get {
            guard let pools = storage[TenantPoolsKey.self] else {
                fatalError("TenantPools no configurado; llama antes a configure(_:).")
            }
            return pools
        }
        set { storage[TenantPoolsKey.self] = newValue }
    }
}

/// **Raíz de composición**: el único sitio del backend donde se cablean las
/// capas entre sí (§2.2).
///
/// Que exista un único fichero así es lo que hace verdad la Regla de dependencia:
/// nadie más conoce a la vez el puerto y su implementación.
public func configure(_ app: Application, config: DatabaseConfig = .fromEnvironment()) async throws {
    // ── Datos ────────────────────────────────────────────────────────────────
    // Un solo *pool*, sin `search_path`: es el del plano de control y también
    // sobre el que la estrategia A abre las transacciones de petición. Su tamaño
    // no crece con el número de clubes, que es la primera razón de §6.4.
    app.databases.use(
        .postgres(configuration: config.sqlConfiguration()),
        as: .control,
        isDefault: true
    )
    app.tenantPools = TenantPools(databases: app.databases) { searchPath in
        config.sqlConfiguration(searchPath: searchPath)
    }

    // La migración del plano de control se aplica **contra `public`** y NO forma
    // parte del juego que recorre los tenants (§4.7).
    app.migrations.add(CreateTenants(), to: .control)

    app.asyncCommands.use(MigrateTenantsCommand(), as: "migrate-tenants")
    app.asyncCommands.use(ProvisionTenantCommand(), as: "provision-tenant")

    // ── HTTP ─────────────────────────────────────────────────────────────────
    let handler = APIHandler(
        unitOfWork: FluentTenantUnitOfWork(controlDatabase: app.db(.control))
    )

    // El transporte se registra sobre un `RoutesBuilder` ya decorado, que es lo
    // que permite conservar el middleware con *design-first* (D-65): la cadena de
    // tenancy —y mañana la de auth (§7.1)— se cuelga aquí, no dentro del handler.
    //
    // `TenantResolutionMiddleware` va el **último** de la cadena a propósito, por
    // el problema conocido entre `@TaskLocal` y la implementación interna de
    // Vapor que documenta `swift-openapi-vapor`.
    let routes = app.grouped(
        TenantResolutionMiddleware(
            extractor: HostSlugExtractor(domainSuffix: config.domainSuffix),
            controlDatabaseID: .control
        )
    )
    try handler.registerHandlers(
        on: VaporTransport(routesBuilder: routes),
        // El prefijo `/v1` del contrato (§5.1). Sale del segundo `server` del
        // *spec*, el de desarrollo local.
        serverURL: URL(string: "/v1")!
    )
}
