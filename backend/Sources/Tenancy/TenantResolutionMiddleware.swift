public import Fluent
public import Vapor

/// Resuelve el club de la petición y lo deja en `TenantContext` (§6.1).
///
/// **Hoy resuelve por `Host` y por cabecera, no por *claim* firmado**, y eso es
/// deuda declarada: §6.1 dice que **el *claim* `club_id` del JWT es
/// autoritativo y el subdominio es solo enrutado**, porque cualquiera puede
/// enviar el `Host` que quiera. §7.7 lo confirma como el hueco más grande del
/// diseño ("nada de §7 se ha ejecutado"). Cuando llegue la validación JWKS,
/// **este middleware es el sitio donde se compara y se rechaza la discrepancia**
/// — no otro.
///
/// - Important: Se cuelga como **último** middleware de la cadena, por el
///   problema conocido entre `@TaskLocal` y la implementación interna de Vapor
///   que documenta `swift-openapi-vapor`.
public struct TenantResolutionMiddleware: AsyncMiddleware {
    private let extractor: HostSlugExtractor
    private let controlDatabaseID: DatabaseID

    /// Cabecera de desarrollo, equivalente a la del spike. Deja probar sin
    /// montar DNS *wildcard* en local.
    public static let developmentHeader = "X-Club"

    public init(extractor: HostSlugExtractor, controlDatabaseID: DatabaseID) {
        self.extractor = extractor
        self.controlDatabaseID = controlDatabaseID
    }

    public func respond(
        to request: Request,
        chainingTo next: any AsyncResponder
    ) async throws -> Response {
        guard let slug = resolveSlug(from: request) else {
            // Petición sin club → 400 (§6.1, "cierre por arriba"). Medido: no se
            // llega a tocar ningún *schema* de tenant.
            throw Abort(.badRequest, reason: "La petición no identifica ningún club")
        }

        let resolver = TenantResolver(database: request.db(controlDatabaseID))
        let tenant: Tenant
        do {
            tenant = try await resolver.resolve(slug: slug)
        } catch TenancyError.unknownTenant {
            // Club desconocido → 404, y literalmente: no existe.
            throw Abort(.notFound, reason: "Club desconocido: \(slug)")
        }

        return try await TenantContext.$current.withValue(tenant) {
            try await next.respond(to: request)
        }
    }

    private func resolveSlug(from request: Request) -> String? {
        if let header = request.headers.first(name: Self.developmentHeader),
           !header.isEmpty {
            return header
        }
        guard let host = request.headers.first(name: .host) else { return nil }
        return extractor.slug(fromHost: host)
    }
}
