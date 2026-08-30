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

    /// El recorrido se pidió sobre una temporada que este club no tiene.
    ///
    /// **No es `seasonNotFound`, y la diferencia es quién puso el id.** Aquél lo
    /// pone la FK de una competición y significa *schema* roto → 500. Éste lo
    /// pone quien llama —el `--season` del job o el cuerpo del disparador— y
    /// significa que ese id no existe aquí → 404.
    ///
    /// Que sean dos y no uno es la lección de `D-84` aplicada a nuestro propio
    /// código: lo que **no** puede hacer un id desconocido es caer a la temporada
    /// vigente y sincronizar otra cosa con cara de éxito.
    case unknownSeason(id: String)

    /// El club declara una federación que **está en el catálogo pero todavía no
    /// tiene adaptador** (`D-17`): hoy, la FCF hasta F9.
    ///
    /// No es un fallo de la pasada —no llega a haber pasada— y por eso no deja
    /// fila en `ingestion_runs`: es un club que aún no se puede sincronizar.
    case federationAdapterMissing(federation: String)
}
