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

    private struct TenantUnitOfWorkKey: StorageKey { typealias Value = FluentTenantUnitOfWork }

    /// **El único acceso a los datos de tenant del proceso, y tiene una sola
    /// conexión a propósito** (`D-100`, A-12·H-77).
    ///
    /// Se construye **una vez**, en `configure`, y lo comparten el servidor y los
    /// comandos. No es un detalle: `db(.control)` ata cada objeto que devuelve a
    /// un *event loop* elegido por turno, y el *pool* es de una conexión por *loop*
    /// (`maxConnectionsPerEventLoop: 1`, abajo). Un objeto, un *loop*, una
    /// conexión: **dos ámbitos de tenant nunca están abiertos a la vez**. Volver a
    /// pedir `db(.control)` en cada sitio rompería eso sin que nada lo dijera.
    ///
    /// Lo vigila `TenantUnitOfWorkTests` (nivel 3): un segundo ámbito no se abre
    /// mientras el primero vive.
    var tenantUnitOfWork: FluentTenantUnitOfWork {
        get {
            guard let unitOfWork = storage[TenantUnitOfWorkKey.self] else {
                fatalError("El acceso de tenant no está configurado; llama antes a configure(_:).")
            }
            return unitOfWork
        }
        set { storage[TenantUnitOfWorkKey.self] = newValue }
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
    clock: any Clock = SystemClock(),
    // `C-E.2`: de dónde sale el actor. En producción, del tenant ambiental —la
    // deuda declarada de F0—; un test puede poner uno que **discrepe** y hacer
    // saltar la guarda de §6.1 sin esperar a JWKS.
    actors: any ActorResolver = AmbientTenantActorResolver()
) async throws {
    // ── Puerto ───────────────────────────────────────────────────────────────
    // El **por defecto** de `serve`: `--port` sigue ganando. Sale de `API_PORT`
    // porque los comandos lo leen de ahí para imprimir sus `curl`.
    app.http.server.configuration.port = APIAddress.fromEnvironment().port

    // ── Datos ────────────────────────────────────────────────────────────────
    // Un solo *pool*, sin `search_path`: es el del plano de control y también
    // sobre el que la estrategia A abre las transacciones de petición. Su tamaño
    // no crece con el número de clubes, que es la primera razón de §6.4.
    //
    // **Una conexión por *event loop*, escrito y no heredado** (`D-100`,
    // A-12·H-77). Era el valor por defecto de `fluent-postgres-driver`, y junto
    // con el acceso de tenant construido una sola vez (abajo) hace que **todas**
    // las transacciones de tenant del proceso vayan en fila. Es lo que impide
    // hoy tres carreras de `INSERT` —temporada, competición e inscripción del
    // enganche— que con dos conexiones darían un `23505` en un 500. **No se sube
    // sin hacer antes seguras esas tres** (la opción B de H-77). Medido: con la
    // ingesta escribiendo, una petición espera como mucho ~0,5 s.
    app.databases.use(
        .postgres(configuration: config.sqlConfiguration(), maxConnectionsPerEventLoop: 1),
        as: .control,
        isDefault: true
    )
    app.tenantPools = TenantPools(databases: app.databases) { searchPath in
        config.sqlConfiguration(searchPath: searchPath)
    }
    app.tenantUnitOfWork = FluentTenantUnitOfWork(controlDatabase: app.db(.control))

    // La migración del plano de control se aplica **contra `public`** y NO forma
    // parte del juego que recorre los tenants (§4.7).
    app.migrations.add(CreateTenants(), to: .control)

    app.asyncCommands.use(MigrateTenantsCommand(), as: "migrate-tenants")
    app.asyncCommands.use(
        ProvisionTenantCommand(federationClients: federationClients), as: "provision-tenant")
    // F6: el adaptador primario de la ingesta (§2.3-b). Es un comando y no una
    // ruta a propósito — un job de sistema no tiene usuario ni JWT que validar.
    app.asyncCommands.use(IngestCommand(), as: "ingest")
    // Herramienta de operación, no contrato: da de alta la **entrada** de la
    // ingesta desde la URL del calendario, mientras `D-67` (F10) no exista.
    app.asyncCommands.use(SeedCompetitionCommand(), as: "seed-competition")
    // F10 · C-F.1: la otra mitad del andamiaje de operación. Sin esto la base de
    // trabajo no puede tener un equipo propio, y sin equipo propio no hay nada
    // que enganchar con `D-67`. `POST /v1/teams` es del backoffice, no de F10.
    app.asyncCommands.use(SeedTeamCommand(), as: "seed-team")

    // ── HTTP ─────────────────────────────────────────────────────────────────
    let handler = APIHandler(
        unitOfWork: app.tenantUnitOfWork,
        federationClients: federationClients,
        clock: clock,
        background: background,
        actors: actors
    )

    // El transporte se registra sobre un `RoutesBuilder` ya decorado, que es lo
    // que permite conservar el middleware con *design-first* (D-65): la cadena de
    // tenancy —y mañana la de auth (§7.1)— se cuelga aquí, no dentro del handler.
    //
    // `TenantResolutionMiddleware` va el **último** de la cadena a propósito, por
    // el problema conocido entre `@TaskLocal` y la implementación interna de
    // Vapor que documenta `swift-openapi-vapor`.
    //
    // **Y esa restricción hace más de lo que parece: cierra el oráculo de
    // tenants** (`A-6`/H-44). Al tener que ir la última, el middleware de auth
    // solo puede colgarse **por fuera**, o sea que corre **antes** — así que un
    // no autenticado se va con un **401** sin que la resolución de tenant llegue
    // a consultar `public.tenants`. Hoy, sin auth, la API **sí** distingue un
    // club que existe (200) de uno que no (404) sin una sola credencial, que es
    // la superficie de enumeración que §9.10 dio por cerrada. Al reordenar esta
    // cadena, saber que se lleva las dos cosas por delante y no solo el
    // `@TaskLocal`.
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
    // **Y lo que no casa con ninguna ruta, también en RFC 7807** (§5.4,
    // `A-14`·H-68). El middleware de un grupo solo corre cuando la ruta casa, así
    // que una ruta fuera del `filter` —la que el backoffice pedirá antes de
    // tiempo— o una errata las servía el `ErrorMiddleware` de Vapor con su
    // `{"error":true,"reason":"Not Found"}`. Se añade **al final** de la cadena
    // global, o sea **por dentro** de ese `ErrorMiddleware`, que se queda como
    // red de último recurso. Es el mismo tipo y la misma traducción: no es un
    // segundo sitio que decida códigos, es el mismo sitio colgado más arriba.
    app.middleware.use(ProblemMiddleware(exposesInternalDetail: app.environment != .production))

    try handler.registerHandlers(
        on: VaporTransport(routesBuilder: routes),
        // El prefijo `/v1` del contrato (§5.1). Sale del segundo `server` del
        // *spec*, el de desarrollo local.
        serverURL: URL(string: "/v1")!
    )
}
