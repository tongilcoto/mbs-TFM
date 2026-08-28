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
        let tenant = try await resolveTenant(for: actor)

        return try await TenantRouting.withSearchPath(
            tenant.schemaName,
            on: controlDatabase
        ) { scopedDatabase in
            try await work(FluentRepositories(database: scopedDatabase))
        }
    }
}

extension FluentTenantUnitOfWork {
    /// Reutiliza el tenant que **ya resolvió el middleware** (§6.1) en lugar de
    /// volver a consultarlo.
    ///
    /// Sin esto, un `PATCH` emitía **dos** `SELECT` idénticos sobre
    /// `public.tenants`: uno del middleware y otro de aquí. No era una caché que
    /// faltara —eso sí habría que medirlo antes de añadirlo—, era la **misma
    /// consulta hecha dos veces en la misma petición**.
    ///
    /// Se conserva la resolución para quien llega **sin** tenant ambiental, que
    /// es el caso real del job de ingesta (§2.3-b): no pasa por HTTP, así que no
    /// hay middleware que se lo haya resuelto.
    private func resolveTenant(for actor: ActorContext) async throws -> Tenant {
        if let ambient = TenantContext.current {
            // Si el actor y el ambiente discrepan, algo se ha cruzado. Se
            // rechaza en vez de elegir uno, que es el criterio de §6.1.
            guard ambient.slug == actor.clubSlug.value else {
                throw TenancyError.tenantMismatch(
                    host: ambient.slug, claim: actor.clubSlug.value)
            }
            return ambient
        }
        return try await TenantResolver(database: controlDatabase)
            .resolve(slug: actor.clubSlug.value)
    }
}

/// Contenedor de repositorios ya atados a la conexión del ámbito.
struct FluentRepositories: Repositories {
    let database: any Database

    var clubs: any ClubRepository { FluentClubRepository(database: database) }
    var seasons: any SeasonRepository { FluentSeasonRepository(database: database) }
    var competitions: any CompetitionRepository { FluentCompetitionRepository(database: database) }
}
