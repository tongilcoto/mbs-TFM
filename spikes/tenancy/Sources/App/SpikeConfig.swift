import FluentPostgresDriver
import Vapor

/// Coordenadas del Postgres del spike. Todo por entorno para que CI pueda apuntar
/// a su servicio Postgres sin tocar código.
public struct SpikeConfig: Sendable {
    public var hostname: String
    public var port: Int
    public var username: String
    public var password: String
    public var database: String

    public static func fromEnvironment() -> SpikeConfig {
        .init(
            hostname: Environment.get("DB_HOST") ?? "localhost",
            port: Environment.get("DB_PORT").flatMap(Int.init) ?? 5433,
            username: Environment.get("DB_USER") ?? "tfm",
            password: Environment.get("DB_PASSWORD") ?? "tfm",
            database: Environment.get("DB_NAME") ?? "tfm_spike"
        )
    }

    /// Las mismas credenciales, pero apuntando al **pooler en modo transacción**
    /// (PgBouncer en el compose, Supavisor en Supabase) en lugar de a Postgres directo.
    ///
    /// El driver no se entera: un pooler habla el mismo protocolo de cable. Lo que
    /// cambia es la semántica — cada transacción puede aterrizar en una conexión de
    /// servidor distinta — y eso es exactamente lo que `PoolerTests` pone a prueba.
    public static func viaPooler() -> SpikeConfig {
        var config = fromEnvironment()
        config.hostname = Environment.get("POOLER_HOST") ?? config.hostname
        config.port = Environment.get("POOLER_PORT").flatMap(Int.init) ?? 6432
        return config
    }

    /// - Parameter searchPath: cuando no es `nil`, el driver emite `SET search_path TO …`
    ///   **al abrir cada conexión** del pool (PostgresConnectionSource). Es la base de la
    ///   estrategia B: un pool por tenant, con el schema fijado desde el nacimiento de la conexión.
    ///
    ///   Ojo: ese `SET` es **de sesión**. Detrás de un pooler en modo transacción, la sesión
    ///   del driver ya no se corresponde con una conexión de servidor, y el `SET` deja de
    ///   significar lo que parece. Ver `PoolerTests`.
    public func sqlConfiguration(searchPath: [String]? = nil) -> SQLPostgresConfiguration {
        var configuration = SQLPostgresConfiguration(
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .disable
        )
        configuration.searchPath = searchPath
        return configuration
    }
}

extension DatabaseID {
    /// Pool del plano de control: `public`, sin `search_path` de tenant.
    /// Es donde vive `public.tenants` (§4.7, §6).
    public static let control = DatabaseID(string: "control")

    /// Pool dedicado de un tenant (estrategia B).
    public static func tenant(_ schema: String) -> DatabaseID {
        DatabaseID(string: "tenant:\(schema)")
    }
}
