import Fluent
import Vapor

/// Resolución del tenant (§6.1). En el backend real el slug sale del subdominio o del
/// claim `club_id` del JWT validado contra Supabase (§7.1/§7.2); aquí se acepta también
/// una cabecera para poder probar el enrutado sin montar el auth.
///
/// Lo que el spike valida no es *cómo* se obtiene el slug, sino que a partir de él el
/// acceso a datos queda encerrado en un schema.
public struct TenantResolutionMiddleware: AsyncMiddleware {
    public init() {}

    public func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let slug = Self.slug(from: request) else {
            throw Abort(.badRequest, reason: "No se pudo resolver el club (subdominio o cabecera X-Club).")
        }
        guard let record = try await TenantRecord.find(slug: slug, on: request.db(.control)) else {
            throw Abort(.notFound, reason: TenancyError.unknownTenant(slug).description)
        }
        request.tenant = Tenant(record)
        // Correlación por tenant en los logs (§8.2).
        request.logger[metadataKey: "tenant"] = .string(record.slug)
        return try await next.respond(to: request)
    }

    static func slug(from request: Request) -> String? {
        if let header = request.headers.first(name: "X-Club"), !header.isEmpty {
            return header
        }
        guard let host = request.headers.first(name: .host)?.split(separator: ":").first else {
            return nil
        }
        let labels = host.split(separator: ".")
        guard labels.count >= 3 else { return nil }
        return String(labels[0])
    }
}
