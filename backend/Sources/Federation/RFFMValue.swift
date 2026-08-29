public import struct Foundation.Date
import struct Foundation.Calendar
import struct Foundation.DateComponents
import struct Foundation.TimeZone
import struct Foundation.CharacterSet
public import struct Domain.WallClockTime
import enum Application.FederationError

/// Las coerciones campo a campo de la RFFM.
///
/// **Todo llega como cadena, sin excepción** ([Anexo RFFM §F.11]): nunca hay
/// números ni booleanos, y las banderas son `"0"`/`"1"`. Así que la frontera entre
/// "lo que dice la fuente" y "lo que entiende el modelo" es un puñado de funciones
/// puras, y aquí están todas juntas a propósito: es la lista de rarezas del anexo
/// hecha código, y se lee al lado de él.
///
/// **Ninguna de estas reglas se deduce.** Cada una cita la observación que la
/// exige, y las que el volcado del 2026-08-28 corrigió lo dicen (§F.15).
public enum RFFMValue {

    // ── Marcador ─────────────────────────────────────────────────────────────

    /// Un marcador, o `nil` si la fuente no dice nada.
    ///
    /// **`""` y `"0"` no son intercambiables** (§F.11) y aquí está la frontera que
    /// lo respeta: vacío → `nil` (*"no se ha jugado"*, §F.5), `"0"` → `0`
    /// (*"empataron a cero"*). Colapsar los dos es exactamente lo que `D-56`
    /// prohíbe, y su consecuencia sería escribir ceros en toda la liga.
    ///
    /// **El signo se preserva.** El parser de la app heredada filtraba todo lo que
    /// no fuese dígito, así que convertía `-3` en `3` (§F.11).
    public static func score(_ raw: String?) throws -> Int? {
        guard let cleaned = sanitised(raw) else { return nil }
        guard let value = Int(cleaned) else {
            throw FederationError.malformedResponse(
                field: "goles", reason: #"no es un entero: "\#(cleaned)""#
            )
        }
        return value
    }

    // ── Fecha y hora ─────────────────────────────────────────────────────────

    /// `"13-09-2026"` → fecha de calendario.
    ///
    /// **No es ISO** (§F.5), y el mismo proveedor usa `yyyy-MM-dd` en sus
    /// catálogos (§F.11), así que el parseo va **por campo** y nunca por un
    /// formateador genérico que acepte las dos.
    ///
    /// Se construye **en UTC**, no en `Europe/Madrid`, por el mismo motivo que
    /// `SeasonLabel` documenta para sus fechas derivadas: es una fecha de
    /// calendario sin hora —columna `date` en Postgres— y con huso local la
    /// medianoche caería el día **anterior** en UTC.
    public static func matchDate(_ raw: String?) throws -> Date? {
        guard let cleaned = sanitised(raw) else { return nil }
        let parts = cleaned.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let day = Int(parts[0]), let month = Int(parts[1]), let year = Int(parts[2]),
              parts[0].count == 2, parts[1].count == 2, parts[2].count == 4
        else {
            throw FederationError.malformedResponse(
                field: "fecha", reason: #"se esperaba "DD-MM-AAAA", llegó "\#(cleaned)""#
            )
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // `date(from:)` devuelve `nil` si la fecha no existe — un 31 de febrero
        // publicado por la fuente entra por aquí, y es un fallo de la fuente.
        guard let date = calendar.date(from: components), calendar.dateComponents([.day], from: date).day == day
        else {
            throw FederationError.malformedResponse(
                field: "fecha", reason: #"fecha inexistente: "\#(cleaned)""#
            )
        }
        return date
    }

    /// `"12:00"` → `WallClockTime`. Ausente o vacía → `nil`.
    ///
    /// **Ninguna de las dos es un error** (§F.5): el calendario se publica primero
    /// entero y sin horas, y la franja se fija el domingo anterior. La muestra 2
    /// del anexo ni siquiera **trae el campo**, de ahí el `String?`.
    public static func kickoff(_ raw: String?) throws -> WallClockTime? {
        guard let cleaned = sanitised(raw) else { return nil }
        let parts = cleaned.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              let time = WallClockTime(hour: hour, minute: minute)
        else {
            throw FederationError.malformedResponse(
                field: "hora", reason: #"se esperaba "HH:mm", llegó "\#(cleaned)""#
            )
        }
        return time
    }

    // ── Campo de juego ───────────────────────────────────────────────────────

    /// Nombre del campo, sin la marca federativa.
    ///
    /// El sufijo `(HA)` aparecía en **240 de 240** nombres (§F.11) y el anexo
    /// proponía una regex de solo `HA`, anclada como sufijo. **El volcado del
    /// 2026-08-28 la desmintió por partida doble** (§F.15): existe `(HB)`
    /// —`"… MARTIN TEMIÑO (HB)(HB)"`— y aparece **en medio** —`"… PEDREGAL 2 (HA)
    /// ANT. DEHESA VIEJA"`—. Así que se quita la marca **esté donde esté**, y se
    /// recolocan los espacios que deja.
    public static func venue(_ raw: String?) -> String? {
        guard var text = raw, !text.isEmpty else { return nil }
        for marker in ["(HA)", "(HB)", "(H.A.)", "(H.B.)"] {
            text = text.replacingOccurrences(of: marker, with: " ")
        }
        let collapsed = text.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    // ── Identificador de club ────────────────────────────────────────────────

    /// El `federation_club_id` (§3.7), sacado del **nombre del fichero del
    /// escudo** — que es donde está, porque el objeto de partido no tiene campo de
    /// club (§F.4).
    ///
    /// Formato observado: `{00100}_{id_club}_{etiqueta}.{ext}`, con `00100`
    /// constante y **la extensión variable** — incluida `.JPG` en mayúsculas
    /// (§F.15).
    ///
    /// **Del `?nova=1` de §F.11 no hay que hacer nada, y conviene decir por qué**
    /// para que nadie añada la línea que no hace falta: el anexo pide quitarlo *"si
    /// la ruta se usa como clave"*, y aquí la clave no es la ruta sino el segundo
    /// segmento del nombre. La consulta va al final, detrás de la extensión, así
    /// que no lo toca. Lo comprobó una **mutación no detectada** (Plan §4.2): al
    /// romper el descarte del *query*, ningún test cayó — porque no protegía nada.
    /// El test de tolerancia se queda; la línea defensiva, no.
    ///
    /// **Devuelve `nil` en vez de fallar, y es deliberado.** §F.4 avisa de que
    /// esto es una **inferencia sobre el nombre de un fichero, no un contrato**:
    /// si un club cambia de escudo, la clave puede cambiar. §3.7 exige que la
    /// ingesta *tolere el fallo y degrade* — el paso 2 de la cadena de
    /// emparejamiento existe justo para esto.
    public static func federationClubID(fromCrestPath path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        guard let filename = path.split(separator: "/").last else { return nil }
        let segments = filename.split(separator: "_", omittingEmptySubsequences: false)
        // Tres segmentos como mínimo: prefijo, id y **al menos** una etiqueta. Las
        // etiquetas llevan `_` dentro con frecuencia, así que no se acota por arriba.
        guard segments.count >= 3, segments[0] == "00100" else { return nil }
        let candidate = String(segments[1])
        guard !candidate.isEmpty, candidate.allSatisfy(\.isNumber) else { return nil }
        return candidate
    }

    // ── Nombre de equipo ─────────────────────────────────────────────────────

    /// El nombre del equipo, partido en club y letra.
    ///
    /// La RFFM embebe la letra **entre comillas simples** al final
    /// —`"C.D. FUTBOL TRES CANTOS 'A'"`— y hay clubes que no la llevan
    /// —`"C.D. EL ESCORIAL"`—, así que `letter` es opcional (§F.5).
    ///
    /// Aquí no se normaliza nada más: la grafía se guarda como viene y se deja a
    /// corrección manual (§F.5, y la política de campo *descriptivo* de §3.7). La
    /// normalización para **emparejar** —sin acentos, sin puntuación— es otra cosa
    /// y vive en la cadena de §3.7, que es **F4**.
    public static func teamName(_ raw: String) -> (name: String, letter: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let characters = Array(trimmed)
        // `X 'A'`: cuatro caracteres de cola y algo delante.
        guard characters.count >= 5,
              characters[characters.count - 1] == "'",
              characters[characters.count - 3] == "'",
              characters[characters.count - 4] == " "
        else {
            return (trimmed, nil)
        }
        let letter = characters[characters.count - 2]
        guard letter.isLetter else { return (trimmed, nil) }
        return (String(characters[0..<(characters.count - 4)]), String(letter))
    }

    // ── Interno ──────────────────────────────────────────────────────────────

    /// Quita espacios, espacios duros y `&nbsp;`, y devuelve `nil` si no queda
    /// nada. **Vacío no es un valor** (`D-56`): esta es la función que lo aplica.
    ///
    /// El `&nbsp;` sin descodificar dentro de campos numéricos está observado en
    /// §F.11; el espacio duro `\u{00A0}` es lo mismo ya descodificado.
    private static func sanitised(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = raw
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }
}
