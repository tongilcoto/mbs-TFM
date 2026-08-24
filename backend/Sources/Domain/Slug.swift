/// Identificador interno legible, usado en rutas, subdominios y claves de Storage.
///
/// **Value Object con invariante** (§4.1): el `pattern` del *spec*
/// (`^[a-z0-9]+(-[a-z0-9]+)*$`) lo hace cumplir **este tipo**, no el código
/// generado — el generador ignora `pattern` (D-65). Se valida aquí y no en el
/// adaptador para que la ruta de ingesta (§2.3-b), que no pasa por HTTP, quede
/// sujeta a la misma regla.
///
/// Es **inmutable** por diseño (§3.2): cambiarlo huérfanaría los *assets* ya
/// almacenados y rompería el enrutado por subdominio (§6.1).
public struct Slug: Hashable, Sendable {
    public let value: String

    public init(_ value: String) throws {
        guard Self.isValid(value) else {
            throw DomainError.invalidValue(
                field: "slug",
                reason: "debe ser minúsculas, dígitos y guiones simples, sin guiones al borde"
            )
        }
        self.value = value
    }

    /// Equivalente a `^[a-z0-9]+(-[a-z0-9]+)*$`, escrito a mano para no arrastrar
    /// `Foundation` al Dominio: un *target* sin dependencias es lo que impide que
    /// alguien importe Fluent aquí por descuido (§2.2).
    static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        var previousWasHyphen = true  // fuerza que no empiece por guion
        for character in value {
            switch character {
            case "a"..."z", "0"..."9":
                previousWasHyphen = false
            case "-":
                if previousWasHyphen { return false }  // guion inicial o doble
                previousWasHyphen = true
            default:
                return false
            }
        }
        return !previousWasHyphen  // ni termina en guion
    }
}
