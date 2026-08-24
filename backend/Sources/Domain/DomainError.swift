/// Errores de invariante del Dominio.
///
/// El Dominio **no conoce HTTP**: no hay códigos de estado aquí. Traducir a
/// RFC 7807 es tarea del adaptador primario (§5.4).
public enum DomainError: Error, Equatable, Sendable {
    /// Un valor no cumple la invariante de su *Value Object* (§4.1).
    case invalidValue(field: String, reason: String)
}
