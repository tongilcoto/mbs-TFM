/// Fallos de orquestación, distintos de los de invariante (`DomainError`).
///
/// Como el Dominio, **no conoce HTTP**: la traducción a RFC 7807 la hace el
/// adaptador primario (§5.4).
public enum ApplicationError: Error, Equatable, Sendable {
    /// El *schema* del tenant existe pero no tiene club dentro. Es un fallo de
    /// **provisión** (§6.3), no un 404 de negocio.
    case tenantNotProvisioned(slug: String)
}
