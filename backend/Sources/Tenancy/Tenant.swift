/// Tenant resuelto para una petición o para una pasada de ingesta (§6.1).
public struct Tenant: Sendable, Equatable {
    public let slug: String
    public let schemaName: String

    public init(slug: String, schemaName: String) {
        self.slug = slug
        self.schemaName = schemaName
    }
}

public enum TenancyError: Error, Equatable, Sendable {
    /// Petición sin club → **400** (§6.1, "cierre por arriba").
    case tenantNotResolved
    /// Club desconocido → **404**. Medido: no se llega a tocar ningún *schema*.
    case unknownTenant(slug: String)
    /// El `Host` dice un club y el *claim* firmado dice otro. **Se rechaza**, no
    /// se da prioridad a ninguno: eso evita la clase entera de confusiones (§6.1).
    case tenantMismatch(host: String, claim: String)
    case notASQLDatabase
}
