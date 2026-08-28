public import Fluent
public import FluentPostgresDriver
import NIOConcurrencyHelpers

extension DatabaseID {
    /// *Pool* del plano de control: `public`, sin `search_path` de tenant. Es
    /// donde vive `public.tenants` y es también sobre el que la estrategia A
    /// abre las transacciones de petición (§6.4).
    public static let control = DatabaseID(string: "control")

    static func tenant(_ schema: String) -> DatabaseID {
        DatabaseID(string: "tenant:\(schema)")
    }
}

/// Registro perezoso de un *pool* por tenant, con `searchPath` fijado en la
/// configuración del driver.
///
/// **Esto es la estrategia B, y solo vale para migraciones** (§6.4). Su `SET` es
/// de **sesión** y el driver lo emite una sola vez, al abrir la conexión; detrás
/// de un *pooler* en modo transacción cruza filas entre clubes, medido:
///
/// ```
/// · EVIDENCIA · B · vía pooler → A ["2023/24", "2024/25"] · B ["2019/20"] · A otra vez ["2019/20"]
/// ```
///
/// Peor aún, contamina al plano de control y le hace crear DDL **dentro del
/// *schema* de un club**. Leer mal se reintenta; un `CREATE TABLE` en el sitio
/// equivocado, no.
///
/// - Important: **Restricción dura: por conexión directa, nunca por el *pooler***.
///   Supabase publica los dos puertos precisamente por esto.
public final class TenantPools: Sendable {
    private let databases: Databases
    private let makeConfiguration: @Sendable ([String]) -> SQLPostgresConfiguration
    private let registered = NIOLockedValueBox<Set<String>>([])

    public init(
        databases: Databases,
        makeConfiguration: @escaping @Sendable ([String]) -> SQLPostgresConfiguration
    ) {
        self.databases = databases
        self.makeConfiguration = makeConfiguration
    }

    /// `Databases.use` está protegido por *lock* y los drivers se crean bajo
    /// demanda, así que **registrar *pools* en caliente es seguro** — comprobado
    /// en el spike (H1).
    public func databaseID(for schema: String) -> DatabaseID {
        let id = DatabaseID.tenant(schema)
        registered.withLockedValue { seen in
            guard !seen.contains(schema) else { return }
            databases.use(
                .postgres(configuration: makeConfiguration([schema])),
                as: id,
                isDefault: false
            )
            seen.insert(schema)
        }
        return id
    }
}
