public import Fluent
public import Vapor

/// Resuelve el club de la petición y lo deja en `TenantContext` (§6.1).
///
/// **Hoy resuelve por `Host`, no por *claim* firmado**, y eso es deuda declarada: §6.1 dice que **el *claim* `club_id` del JWT es
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

    /// Cabecera de desarrollo, equivalente a la del spike.
    public static let developmentHeader = "X-Club"

    /// **Si esto fuese `true` en producción, sería un conmutador de tenant
    /// abierto**: cualquiera podría mandar `X-Club: otro-club` y leer los datos
    /// de otro. La cabecera la controla el cliente por completo, que es
    /// exactamente la razón por la que §6.1 dice que el `Host` es *enrutado* y
    /// solo el *claim* firmado es autoritativo.
    ///
    /// Se decide **por lista blanca de entornos** (`.development`, `.testing`),
    /// no descartando `.production`: así un entorno nuevo nace con la cabecera
    /// **apagada** en vez de encendida.
    private let allowsDevelopmentHeader: Bool

    public init(
        extractor: HostSlugExtractor,
        controlDatabaseID: DatabaseID,
        allowsDevelopmentHeader: Bool
    ) {
        self.extractor = extractor
        self.controlDatabaseID = controlDatabaseID
        self.allowsDevelopmentHeader = allowsDevelopmentHeader
    }

    /// Lista blanca: cualquier entorno que no sea de desarrollo o test rechaza
    /// la cabecera.
    public static func allowsDevelopmentHeader(in environment: Environment) -> Bool {
        environment == .development || environment == .testing
    }

    public func respond(
        to request: Request,
        chainingTo next: any AsyncResponder
    ) async throws -> Response {
        guard let slug = resolveSlug(from: request) else {
            // Petición sin club → 400 (§6.1, "cierre por arriba"). Medido: no se
            // llega a tocar ningún *schema* de tenant.
            //
            // Se lanza el error de **dominio de tenancy**, no un `Abort`: quien
            // decide el código HTTP y el cuerpo RFC 7807 es `ProblemMiddleware`
            // (§5.4). Este middleware no sabe de códigos.
            throw TenancyError.tenantNotResolved
        }

        // Club desconocido → 404 literal, y lo traduce `ProblemMiddleware`.
        let resolver = TenantResolver(database: request.db(controlDatabaseID))
        let tenant = try await resolver.resolve(slug: slug)

        return try await TenantContext.$current.withValue(tenant) {
            try await next.respond(to: request)
        }
    }

    private func resolveSlug(from request: Request) -> String? {
        if allowsDevelopmentHeader,
           let header = request.headers.first(name: Self.developmentHeader),
           !header.isEmpty {
            return header
        }
        guard let host = request.headers.first(name: .host) else { return nil }
        return extractor.slug(fromHost: host)
    }
}
