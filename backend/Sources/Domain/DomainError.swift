public import struct Foundation.Date

/// Errores de invariante del Dominio.
///
/// El Dominio **no conoce HTTP**: no hay códigos de estado aquí. Traducir a
/// RFC 7807 es tarea del adaptador primario (§5.4).
public enum DomainError: Error, Equatable, Sendable {
    /// Un valor no cumple la invariante de su *Value Object* (§4.1).
    ///
    /// El adaptador lo traduce a **422**: el cuerpo llegó bien formado pero dice
    /// algo que el dominio no admite.
    case invalidValue(field: String, reason: String)

    /// El campo dejó de ser editable porque la entidad ya se sincronizó (`D-22`).
    ///
    /// **No es lo mismo que `invalidValue`, y por eso es un caso aparte**: el
    /// valor puede ser perfectamente válido —lo que no es válido es el
    /// *momento*—. El adaptador lo traducirá a **409**, no a 422 (§5.4).
    case notEditableAfterSync(field: String)

    /// La coordenada de la competición sigue siendo válida pero **ya no apunta a
    /// esta competición** (`D-84`): la fuente devuelve un calendario de otra.
    ///
    /// No es un dato mal formado ni una invariante rota por el usuario: es la
    /// constatación de que el proveedor ignora el parámetro `temporada` (`D-84` enmendada).
    case federationSourceMismatch(expected: String, found: String)

    /// El calendario que llega es de **otra temporada** (`D-91`): la mediana de
    /// sus fechas cae fuera de la ventana de la `Season`.
    ///
    /// Hermano del anterior y por el mismo motivo —el proveedor no falla, sirve
    /// otra cosa— pero con la **evidencia distinta**: aquél compara el nombre de
    /// la competición, que es idéntico entre temporadas ([Anexo RFFM §F.17]), y
    /// éste las fechas, que son lo único que no puede ser eco (§F.16).
    ///
    /// Lleva la fecha **sin formatear**: el Dominio no conoce la zona horaria ni
    /// el idioma del que va a leer el problema (§5.4).
    case federationSeasonMismatch(seasonLabel: String, calendarMedian: Date)

    /// El equipo ya está enganchado a **otro** `codigo_equipo` (`D-67`, F10).
    ///
    /// Hermano de `notEditableAfterSync` —los dos son **409**, los dos dicen que
    /// el momento es el problema y no el valor— pero con una diferencia que el
    /// *spec* subraya: **éste tiene salida**. Se engancha otro equipo, o se
    /// corrige la URL antes de confirmar.
    ///
    /// Lleva los dos códigos porque sin ellos el problema no se puede depurar:
    /// *"ya está enganchado"* no dice a qué, y el administrador tiene doce
    /// equipos.
    case alreadyLinkedToFederation(existing: String, incoming: String)

    /// La URL de calendario que han pegado **no es de esta federación, o no se
    /// puede leer** (`D-97`, `D-22`, F10).
    ///
    /// # Por qué el Dominio tiene un error sobre una URL que no conoce
    ///
    /// Porque no la conoce, justamente. El *host* de la RFFM, sus nombres de
    /// parámetro y su catálogo de `tipojuego` son del **universo de datos de esa
    /// federación**, y ese universo no sale del adaptador (`D-97`). Lo que sale
    /// es esto: la única forma del problema que un caso de uso puede entender
    /// sin saber con qué federación está hablando.
    ///
    /// Es hermano de `invalidValue` pero **no es él**, y la diferencia es la que
    /// decide el código HTTP: un `invalidValue` es un **campo** del modelo que
    /// dice algo inadmisible; esto es **el sobre** del que tenían que salir los
    /// cuatro parámetros de la coordenada. Cuando el sobre no se puede abrir no
    /// hay ningún valor que juzgar.
    ///
    /// Lleva la URL y el motivo por separado: el motivo lo escribe el adaptador
    /// —es lo único que sabe por qué— y la URL la necesita el administrador, que
    /// tiene doce equipos y acaba de pegar una de doce pestañas.
    case unreadableFederationURL(url: String, reason: String)
}
