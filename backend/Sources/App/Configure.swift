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
public func configure(
    _ app: Application,
    config: DatabaseConfig = .fromEnvironment(),
    // Se inyecta para que los tests de nivel 4 puedan poner un doble **sin red**
    // (Plan §4.4: la batería tiene que ser determinista). En producción es el
    // catálogo de `D-17`.
    federationClients: any FederationClientProvider = CatalogFederationClientProvider(),
    background: any BackgroundWork = DetachedBackgroundWork(),
    // **El reloj también se inyecta**, y no por simetría: de él sale cuál es la
    // temporada vigente (§3.2). Con `SystemClock` un test tendría que sembrar la
    // temporada del año en curso y **caducaría** el 1 de julio siguiente, con el
    // fallo apareciendo meses después y sin relación con el cambio que lo
    // destapó.
    clock: any Clock = SystemClock()
) async throws {
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
    // F6: el adaptador primario de la ingesta (§2.3-b). Es un comando y no una
    // ruta a propósito — un job de sistema no tiene usuario ni JWT que validar.
    app.asyncCommands.use(IngestCommand(), as: "ingest")
    // Herramienta de operación, no contrato: da de alta la **entrada** de la
    // ingesta desde la URL del calendario, mientras `D-67` (F10) no exista.
    app.asyncCommands.use(SeedCompetitionCommand(), as: "seed-competition")

    // ── HTTP ─────────────────────────────────────────────────────────────────
    let handler = APIHandler(
        unitOfWork: FluentTenantUnitOfWork(controlDatabase: app.db(.control)),
        federationClients: federationClients,
        clock: clock,
        background: background
    )

    // El transporte se registra sobre un `RoutesBuilder` ya decorado, que es lo
    // que permite conservar el middleware con *design-first* (D-65): la cadena de
    // tenancy —y mañana la de auth (§7.1)— se cuelga aquí, no dentro del handler.
    //
    // `TenantResolutionMiddleware` va el **último** de la cadena a propósito, por
    // el problema conocido entre `@TaskLocal` y la implementación interna de
    // Vapor que documenta `swift-openapi-vapor`.
    let routes = app.grouped(
        // El primero del todo, para que vea la petición tal cual llega y la
        // respuesta ya traducida a RFC 7807. Inerte salvo con `HTTP_TRACE=1`
        // fuera de producción.
        RequestTraceMiddleware(
            isEnabled: RequestTraceMiddleware.isEnabled(in: app.environment)
        ),
        // Envuelve a todos los de dentro, así que traduce también lo que lance
        // el de tenancy (§5.4).
        ProblemMiddleware(exposesInternalDetail: app.environment != .production),
        TenantResolutionMiddleware(
            extractor: HostSlugExtractor(domainSuffix: config.domainSuffix),
            controlDatabaseID: .control,
            // Fuera de desarrollo y test, la cabecera `X-Club` deja de existir:
            // es un dato que controla el cliente y aceptarla en producción sería
            // dejar abierto un conmutador de tenant (§6.1).
            allowsDevelopmentHeader: TenantResolutionMiddleware
                .allowsDevelopmentHeader(in: app.environment)
        )
    )
    try handler.registerHandlers(
        on: VaporTransport(routesBuilder: routes),
        // El prefijo `/v1` del contrato (§5.1). Sale del segundo `server` del
        // *spec*, el de desarrollo local.
        serverURL: URL(string: "/v1")!
    )
}
