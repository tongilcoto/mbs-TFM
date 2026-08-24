public import FluentPostgresDriver
import Vapor

/// Coordenadas de Postgres, todas por entorno para que CI apunte a su propio
/// servicio sin tocar código.
public struct DatabaseConfig: Sendable {
    public var hostname: String
    public var port: Int
    public var username: String
    public var password: String
    public var database: String

    /// Sufijo de dominio del despliegue, del que se recorta el slug (§6.1).
    public var domainSuffix: String

    public static func fromEnvironment() -> DatabaseConfig {
        .init(
            hostname: Environment.get("DB_HOST") ?? "localhost",
            port: Environment.get("DB_PORT").flatMap(Int.init) ?? 5434,
            username: Environment.get("DB_USER") ?? "tfm",
            password: Environment.get("DB_PASSWORD") ?? "tfm",
            database: Environment.get("DB_NAME") ?? "tfm",
            domainSuffix: Environment.get("DOMAIN_SUFFIX") ?? "localhost"
        )
    }

    public func sqlConfiguration(searchPath: [String]? = nil) -> SQLPostgresConfiguration {
        var configuration = SQLPostgresConfiguration(
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .disable
        )
        // Solo lo usan las migraciones (estrategia B, §6.4). En el camino de las
        // peticiones va siempre `nil`.
        configuration.searchPath = searchPath
        return configuration
    }
}
