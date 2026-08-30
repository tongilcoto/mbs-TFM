import Foundation

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

    /// Equivalente a `^[a-z0-9]+(-[a-z0-9]+)*$`, escrito a mano y no con
    /// `NSRegularExpression`: son nueve líneas, no compila un autómata en cada
    /// llamada y dice exactamente lo mismo que el `pattern` del *spec*.
    ///
    /// (El fichero **sí** importa `Foundation` desde `D-82`, que necesita
    /// `folding`. Lo que la Regla de dependencia de §2.2 prohíbe aquí es Vapor y
    /// Fluent; `Foundation` es biblioteca estándar y ya entra por
    /// `NormalizedName` y por `Identifiers`.)
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

extension Slug {
    /// Deriva el slug de un nombre de club (`D-82`).
    ///
    /// # Mecánica, sin diccionario
    ///
    /// El *spec* dice que el servidor lo genera **del nombre** al crear la fila,
    /// y quien crea `OpponentClub` es la ingesta (§3.7). La tentación es limpiar
    /// la forma jurídica —que `"CELTIC CASTILLA C.F."` dé `"celtic-castilla"`—,
    /// y es la que hay que resistir: exigiría una lista de "C.F.", "C.D.",
    /// "S.A.D.", "U.D.", "E.F.M.O."… que es una segunda fuente de verdad, se
    /// queda corta con la primera federación nueva, y **no compra nada**: el
    /// slug no se muestra (§3.2), solo se enruta y se usa de nombre de fichero.
    ///
    /// # `throws`, y no un valor de relleno
    ///
    /// Si del nombre no queda ninguna letra ni dígito no hay slug que dar. Un
    /// `"club-1"` de relleno sería inventar identidad —y esa identidad acaba en
    /// una clave de Storage (`D-19`) y en un `UNIQUE` (§3.5)—. La ingesta deja
    /// la fila fuera y la reporta, que es lo mismo que hace con cualquier otra
    /// degradación de §3.7.
    ///
    /// **Esto no resuelve las colisiones**, y no puede: dos nombres distintos
    /// pueden dar el mismo slug y saberlo exige consultar lo que ya hay. Ese
    /// desempate es del caso de uso (`D-82`), que es quien tiene repositorio.
    public init(derivedFrom name: String) throws {
        // Mismo plegado y mismo `locale` fijo que `NormalizedName`, y por la
        // misma razón: determinismo. Aquí `Foundation` sí entra —`Slug` ya vive
        // en el Dominio y `folding` es biblioteca estándar, no framework (§2.2).
        let folded = name.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()

        // Al revés que `NormalizedName`, que **borra** las fronteras para que
        // `"C.D."` y `"CD"` empareien: aquí cada corrida de lo que no es letra
        // ni dígito se convierte en **un** guion. Son dos reglas opuestas a
        // propósito — una compara, la otra nombra.
        var segments: [String] = []
        var current = ""
        for character in folded {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                segments.append(current)
                current = ""
            }
        }
        if !current.isEmpty { segments.append(current) }

        guard !segments.isEmpty else {
            throw DomainError.invalidValue(
                field: "slug",
                reason: #"no se puede derivar un slug de "\#(name)""#
            )
        }

        try self.init(segments.joined(separator: "-"))
    }
}
