import Fluent
import FluentPostgresDriver
import Vapor

/// - Parameter config: coordenadas de la BD. Se parametriza para que `PoolerTests` pueda
///   levantar la **misma** aplicación contra el pooler en modo transacción sin tocar nada
///   más: la comparación solo dice algo si el código bajo prueba es idéntico.
public func configure(_ app: Application, config: SpikeConfig = .fromEnvironment()) async throws {
    app.spikeConfig = config

    if let raw = Environment.get("TENANT_STRATEGY"), let strategy = TenantRoutingStrategy(rawValue: raw) {
        app.tenantRoutingStrategy = strategy
    }

    // Pool del plano de control: `public`, sin search_path de tenant.
    // Es también el pool sobre el que trabaja la estrategia A (SET LOCAL por transacción).
    app.databases.use(
        .postgres(configuration: config.sqlConfiguration()),
        as: .control,
        isDefault: true
    )

    app.tenantPools = TenantPools(databases: app.databases, config: config)

    // La migración del plano de control se aplica una vez, contra public, y NO
    // forma parte del juego que recorre los tenants (§4.7).
    app.migrations.add(CreateTenants(), to: .control)

    app.asyncCommands.use(MigrateTenantsCommand(), as: "migrate-tenants")
    app.asyncCommands.use(ProvisionTenantCommand(), as: "provision-tenant")

    try routes(app)
}
