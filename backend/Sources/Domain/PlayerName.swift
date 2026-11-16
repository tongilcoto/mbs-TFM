import struct Foundation.Locale

/// El nombre del jugador, como se guarda (`D-120`): **«NOMBRE APELLIDOS», limpio
/// y en mayúsculas**.
///
/// # Por qué en mayúsculas, y no como lo teclea cada uno
///
/// La federación publica los nombres en mayúsculas, y el club los teclea como
/// quiere. Guardarlos tal cual dejaría dos formas en la misma tabla; pasarlos a
/// «Nombre Apellidos» en el servidor guardaría mal las partículas («De la Fuente»
/// o «de la Fuente»). Así que se guardan en mayúsculas, y **la web los formatea
/// al pintarlos** (`D-120`).
///
/// # Por qué la regla está aquí y no en el catálogo
///
/// La comprueba el dominio para que valga igual en el alta, la corrección y la
/// sincronización, que no pasa por el catálogo. Un nombre que no vale es un 422
/// `INVALID_VALUE` con el `detail` `fullName: <motivo>` (R6.4).
///
/// # Lo que este tipo no hace
///
/// **No compara nombres.** «El mismo nombre» de la sincronización (sin tildes ni
/// diéresis, con la eñe distinta) y la búsqueda del alta (sin tildes, palabra a
/// palabra) son claves derivadas de este, y llegan con su rebanada (R6.14, R6.7).
public struct PlayerName: Hashable, Sendable {
    /// El nombre limpio, en mayúsculas.
    public let value: String

    /// El largo máximo, el del catálogo (`PlayerFullName.maxLength`).
    public static let maxLength = 120

    public init(_ raw: String) throws {
        // **La forma compuesta primero**: «é» puede llegar como una pieza o como
        // «e» más el acento, y sin esto «JOSÉ» serían dos nombres en la base.
        let words = raw.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        let cleaned = words.joined(separator: " ")

        guard !cleaned.isEmpty else {
            throw Self.invalid("no puede estar vacío")
        }
        guard cleaned.count <= Self.maxLength else {
            throw Self.invalid("como mucho \(Self.maxLength) caracteres")
        }
        guard cleaned.allSatisfy(Self.isAllowed) else {
            throw Self.invalid("solo puede llevar letras, espacios, guion y apóstrofo")
        }
        guard words.allSatisfy({ $0.contains(where: \.isLetter) }) else {
            throw Self.invalid("cada palabra tiene que llevar letras")
        }
        guard words.count >= 2 else {
            throw Self.invalid("tiene que llevar el nombre y al menos un apellido")
        }

        // Con el idioma fijo: el del sistema podría cambiar alguna letra.
        self.value = cleaned.uppercased(with: Locale(identifier: "es_ES"))
    }

    /// Letras (con tildes, eñe y diéresis), el espacio, el guion y el apóstrofo,
    /// recto o curvo: los dos llegan al copiar de otra página.
    private static func isAllowed(_ character: Character) -> Bool {
        character.isLetter || character == " " || character == "-"
            || character == "'" || character == "’"
    }

    private static func invalid(_ reason: String) -> DomainError {
        .invalidValue(field: "fullName", reason: reason)
    }
}
