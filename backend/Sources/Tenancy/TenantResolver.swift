public import Fluent

/// Resuelve el slug de un club a su *schema* consultando el plano de control.
///
/// Consulta una tabla **cualificada** (`"public"."tenants"`), no una sin
/// cualificar: la resolución de tenant **no puede depender del `search_path`**,
/// que es justo lo que está a punto de fijarse (§6.1). Lo consigue el `space`
/// de `TenantRecord`.
public struct TenantResolver: Sendable {
    private let database: any Database

    public init(database: any Database) {
        self.database = database
    }

    public func resolve(slug: String) async throws -> Tenant {
        guard let record = try await TenantRecord.query(on: database)
            .filter(\.$slug == slug)
            .first()
        else {
            throw TenancyError.unknownTenant(slug: slug)
        }
        return Tenant(slug: record.slug, schemaName: record.schemaName)
    }
}

/// Extrae el slug del `Host`.
///
/// **Contra un sufijo de dominio configurado, no contra un contador de
/// etiquetas** (§6.1). Partir por puntos y quedarse con la primera funciona
/// hasta que alguien pide el ápice: `api.myapp.com` tiene tantas etiquetas como
/// `atleti.myapp.com` y se resolvería como un club llamado "api".
public struct HostSlugExtractor: Sendable {
    /// Sufijo del despliegue, p. ej. `myapp.com`.
    public let domainSuffix: String

    /// Nombres que **nunca** son un club, desde el alta del primero (§6.1).
    public static let reserved: Set<String> = [
        "www", "api", "admin", "app", "status", "mail", "staging",
    ]

    public init(domainSuffix: String) {
        self.domainSuffix = domainSuffix
    }

    /// `nil` si la petición **no es de tenant** (el ápice, o un host ajeno).
    /// Distinto de "club desconocido": eso lo decide `TenantResolver`.
    public func slug(fromHost host: String) -> String? {
        // El `Host` puede traer puerto; el esquema y la ruta no llegan aquí.
        let hostname = String(host.split(separator: ":").first ?? "").lowercased()
        let suffix = "." + domainSuffix.lowercased()

        guard hostname.hasSuffix(suffix) else { return nil }
        let label = String(hostname.dropLast(suffix.count))

        // Exactamente **una** etiqueta delante: `a.b.myapp.com` no es un club.
        guard !label.isEmpty, !label.contains(".") else { return nil }
        guard !Self.reserved.contains(label) else { return nil }
        return label
    }
}
