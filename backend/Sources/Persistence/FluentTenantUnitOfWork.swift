public import Application
import Domain
import Fluent
import Tenancy

/// Implementa el ámbito de tenant (§6.2) con la **estrategia A**: `SET LOCAL
/// search_path` dentro de la transacción de la petición.
///
/// Es el sitio —el único— donde el backend traduce "el club del actor" a un
/// *schema* de Postgres. Todo lo de arriba habla de clubes; todo lo de abajo,
/// de tablas sin cualificar.
public struct FluentTenantUnitOfWork: TenantUnitOfWork {
    private let controlDatabase: any Database

    /// - Parameter controlDatabase: el *pool* del plano de control (`public`).
    ///   Es también sobre el que se abre la transacción del tenant: la estrategia
    ///   A usa **un** *pool*, cuyo tamaño no crece con el número de clubes (§6.4).
    public init(controlDatabase: any Database) {
        self.controlDatabase = controlDatabase
    }

    public func withRepositories<T: Sendable>(
        actor: ActorContext,
        _ work: @escaping @Sendable (any Repositories) async throws -> T
    ) async throws -> T {
        // TODO(F-posterior): esto es una consulta al plano de control **por
        // petición**. Cachear slug→schema es la optimización obvia, pero también
        // es una caché de una decisión de aislamiento: no se añade sin medir ni
        // sin decidir su invalidación. Anotado, no hecho.
        let resolver = TenantResolver(database: controlDatabase)
        let tenant = try await resolver.resolve(slug: actor.clubSlug.value)

        return try await TenantRouting.withSearchPath(
            tenant.schemaName,
            on: controlDatabase
        ) { scopedDatabase in
            try await work(FluentRepositories(database: scopedDatabase))
        }
    }
}

/// Contenedor de repositorios ya atados a la conexión del ámbito.
struct FluentRepositories: Repositories {
    let database: any Database

    var clubs: any ClubRepository { FluentClubRepository(database: database) }
}
