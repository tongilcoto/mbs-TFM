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

    /// **El equipo que designa la ruta no existe** (F10, `C-E.6` → **404**).
    ///
    /// Lo estrena el enganche, que es el primer caso de uso que llega a un equipo
    /// **por su id**: `/v1/teams/{id}/federation-link` (`D-67`). Hasta aquí la
    /// ingesta solo cargaba la lista entera para emparejar (§3.7), así que
    /// *"ese equipo no está"* no era una situación que nadie pudiera provocar.
    ///
    /// Es 404 y no 500, al revés que `tenantNotProvisioned`: el id lo puso quien
    /// llama, así que es un dato suyo que no existe, no un *schema* roto. Mismo
    /// criterio que `unknownSeason`.
    case teamNotFound(id: String)

    /// **La fuente no publicó etiqueta de temporada y hay que crear una**
    /// (F10, `C-C.8` → **400**).
    ///
    /// No es validación por validar: **`Season.label` deriva la ventana de
    /// fechas** que la guarda de `D-91` usa como evidencia (§3.2). Una temporada
    /// rotulada a ojo acepta cualquier calendario o rechaza todos, así que
    /// inventarla no degrada el rótulo — desarma la comprobación de al lado.
    ///
    /// El sobre no promete la etiqueta desde F6-bis (H-08): la FCF no la publica
    /// y en la RFFM es el eco de nuestro propio parámetro ([Anexo RFFM §F.16]).
    /// Por eso el cuerpo del enganche la lleva; cuando tampoco viene ahí, la
    /// salida es dar de alta la temporada antes (`POST /v1/seasons`) — que es lo
    /// mismo que dice `seed-competition` desde F6.
    case seasonLabelUnavailable(federationSeasonID: String)

    /// **La base no responde** (H-23, `D-86` enmendada).
    ///
    /// No es el fallo de una competición: es el fallo del sitio donde se apuntan
    /// los fallos. `D-86` continúa el recorrido *"solo cuando el fallo deja
    /// constancia"*, y con la base caída no la deja — así que este error es la
    /// señal de que **no se continúa**.
    ///
    /// Se distingue de los demás **preguntándole a la base**, no clasificando el
    /// error que llegó: un `PSQLError` de conexión, un *pool* agotado y un relevo
    /// del *pooler* (§6.4) llegan de formas distintas, y una lista de códigos
    /// sería una premisa sobre un sistema ajeno — que es lo que `D-84` enseñó a
    /// no heredar.
    case databaseUnavailable

    /// **La pasada se escribió y no se pudo apuntar** (H-24).
    ///
    /// El ámbito 2 comprometió —los datos están, `last_synced_at` está puesto— y
    /// el ámbito 3 falló. Lo que **no** se hace entonces es registrar la pasada
    /// como fallida: sería escribir una mentira sobre unos datos que sí están, y
    /// dejar tres testigos contradiciéndose. Se lanza esto, que dice exactamente
    /// lo que pasó.
    case runNotRecorded(competitionID: String, reason: String)
}
