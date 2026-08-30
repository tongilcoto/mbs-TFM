/// Fallos de orquestación, distintos de los de invariante (`DomainError`).
///
/// Como el Dominio, **no conoce HTTP**: la traducción a RFC 7807 la hace el
/// adaptador primario (§5.4).
public enum ApplicationError: Error, Equatable, Sendable {
    /// El *schema* del tenant existe pero no tiene club dentro. Es un fallo de
    /// **provisión** (§6.3), no un 404 de negocio.
    case tenantNotProvisioned(slug: String)

    /// La pasada de ingesta se lanzó sobre una competición que no está. No es un
    /// 404 del BFF: quien la lanza es el job (§2.3-b), con un id que sacó de la
    /// propia base — así que esto significa que alguien la borró entre medias.
    case competitionNotFound(id: String)

    /// La competición apunta a una temporada que no está. Es integridad rota:
    /// la FK lo impide, así que solo puede venir de un *schema* a medio migrar.
    case seasonNotFound(id: String)
}
