public import struct Domain.SeasonLabel
import enum Application.FederationError

/// Traduce la etiqueta de temporada de la RFFM al formato del modelo.
///
/// La fuente publica **`"2026-2027"`** ([Anexo RFFM §F.11], y en el sobre del
/// calendario como `calendar.temporada`, §F.15); el modelo usa **`"2026/27"`**
/// (§3.2). La traducción es de aquí y no del Dominio, porque cada federación
/// rotula a su manera y `SeasonLabel` no debe conocer ninguna — lo dice el propio
/// `SeasonLabel` en su documentación.
///
/// # Por qué son nueve líneas con nombre propio en vez de una interpolación
///
/// Porque su forma de fallar es silenciosa. Componer la etiqueta a mano —
/// `"\(años[0])/\(segundo.prefix(2))"` — produce **`"2026/20"`** en vez de
/// `"2026/27"`: cumple el `pattern` del *spec*, deriva unas fechas correctas y se
/// guarda como una temporada bien fechada con la etiqueta mal. Es literalmente el
/// fallo que `D-71` existe para atrapar, y esta ruta **no pasa por el contrato**,
/// así que la única red es esta función y la invariante que invoca.
///
/// De ahí que **no construya la etiqueta y ya**: la pasa por `SeasonLabel`, que
/// comprueba que los dos años son consecutivos. Si la fuente publicase
/// `"2026-2028"`, aquí no se guarda una temporada inventada: se falla.
public enum RFFMSeasonLabel {

    /// `"2026-2027"` → `SeasonLabel("2026/27")`.
    ///
    /// - Throws: `FederationError.malformedResponse` si la cadena no tiene la
    ///   forma de la fuente; `DomainError` si la tiene pero los años no son
    ///   consecutivos — y la distinción es útil: lo primero es que **cambió la
    ///   fuente**, lo segundo que **la fuente se equivocó**.
    public static func parse(_ raw: String) throws -> SeasonLabel {
        let characters = Array(raw)
        guard characters.count == 9, characters[4] == "-",
              let first = fourDigits(characters[0..<4]),
              fourDigits(characters[5..<9]) != nil
        else {
            throw FederationError.malformedResponse(
                field: "temporada",
                reason: #"se esperaba "AAAA-BBBB", llegó "\#(raw)""#
            )
        }

        // Los **dos últimos** dígitos del segundo año, no los dos primeros. Esta
        // línea es la que rompe la comprobación de mutación del Plan §4.2.
        let secondHalf = String(characters[7..<9])
        return try SeasonLabel("\(first)/\(secondHalf)")
    }

    /// Cuatro dígitos ASCII, o `nil`. Sin regex, como `SeasonLabel` y `Slug`:
    /// son nueve caracteres.
    private static func fourDigits(_ slice: ArraySlice<Character>) -> Int? {
        var total = 0
        for character in slice {
            guard ("0"..."9").contains(character), let digit = character.wholeNumberValue
            else { return nil }
            total = total * 10 + digit
        }
        return total
    }
}
