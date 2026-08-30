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
    /// constatación de que el proveedor reutiliza sus códigos entre temporadas.
    case federationSourceMismatch(expected: String, found: String)
}
