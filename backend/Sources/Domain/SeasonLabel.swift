public import struct Foundation.Date
import struct Foundation.Calendar
import struct Foundation.DateComponents
import struct Foundation.TimeZone

/// Etiqueta de la temporada — `"2025/26"`.
///
/// **Value Object con invariante** (§4.1), y con **una regla más que el `pattern`
/// del *spec*** (`D-71`). El contrato declara `^\d{4}/\d{2}$`, que no relaciona
/// las dos mitades: `"2025/20"` lo cumple. Este tipo exige además que la segunda
/// sea el **año siguiente** de la primera.
///
/// # Por qué la regla de más
///
/// `Season` entra por **dos** puertas y solo una pasa por el contrato:
///
/// | Vía | Quién produce la etiqueta | Qué la valida antes de llegar aquí |
/// |---|---|---|
/// | `POST /v1/seasons` | un administrador que la teclea | el `pattern` del *spec* → 400 |
/// | cascada de `/federation-link` (`D-67`) | **nuestro adaptador RFFM**, reformateando | **nada** |
///
/// La RFFM publica la etiqueta como `"2025-2026"` ([Anexo RFFM §F.11]), así que
/// en la ruta de ingesta hay un reformateo de por medio que escribimos nosotros
/// (F2). Su forma de fallar es tomar los dos caracteres equivocados: `"2025/20"`
/// encaja con el `pattern`, deriva unas fechas correctas y se guarda como una
/// temporada bien fechada con la etiqueta mal — y es el `label` el que lleva el
/// `UNIQUE` (§3.5) y el que ve el usuario.
///
/// Validación en **dos capas, deliberada**: la segunda existe porque la ingesta
/// no tiene primera.
///
/// # Dónde está la frontera con el adaptador
///
/// Este tipo es dueño del formato **del modelo** (`"2025/26"`). Traducir
/// `"2025-2026"` es trabajo del adaptador RFFM, no del Dominio: cada federación
/// rotula a su manera y el Dominio no debe conocer ninguna.
public struct SeasonLabel: Hashable, Sendable {
    /// La etiqueta tal cual, en el formato del modelo: `"2025/26"`.
    public let value: String

    /// Año en que arranca la temporada: `2025` en `"2025/26"`.
    public let startYear: Int

    public init(_ value: String) throws {
        guard let startYear = Self.parse(value) else {
            throw DomainError.invalidValue(
                field: "label",
                reason: "debe ser AAAA/AB con AB el año siguiente, como \"2025/26\""
            )
        }
        self.value = value
        self.startYear = startYear
    }

    /// Año en que termina: `2026` en `"2025/26"`.
    public var endYear: Int { startYear + 1 }

    /// Devuelve el año de inicio si la etiqueta es válida, `nil` si no.
    ///
    /// Escrito a mano y sin expresiones regulares, por el mismo motivo que
    /// `Slug`: mantener el Dominio con la mínima superficie de dependencias
    /// (§2.2). Son siete caracteres; no hace falta un motor de regex.
    static func parse(_ value: String) -> Int? {
        let characters = Array(value)
        guard characters.count == 7, characters[4] == "/" else { return nil }

        func digits(_ slice: ArraySlice<Character>) -> Int? {
            var total = 0
            for character in slice {
                guard let digit = character.wholeNumberValue, character.isASCII,
                      ("0"..."9").contains(character)
                else { return nil }
                total = total * 10 + digit
            }
            return total
        }

        guard let start = digits(characters[0..<4]),
              let end = digits(characters[5..<7])
        else { return nil }

        // La comprobación que el `pattern` del spec no sabe hacer. El `% 100`
        // es lo que hace que `"2099/00"` sea válida: 2099 → 2100 → "00".
        guard end == (start + 1) % 100 else { return nil }
        return start
    }
}

extension SeasonLabel {
    /// 1 de julio del año de inicio. **Derivada y no *overridable*** (§3.2).
    public var startDate: Date { Self.day(year: startYear, month: 7, day: 1) }

    /// 30 de junio del año de fin. **Derivada y no *overridable*** (§3.2).
    public var endDate: Date { Self.day(year: endYear, month: 6, day: 30) }

    /// Construye la fecha **en UTC**, no en `Europe/Madrid`.
    ///
    /// Las dos son fechas de calendario sin hora (`format: date` en el *spec*,
    /// columna `date` en Postgres), así que el huso no forma parte del dato. Se
    /// fija UTC para que la representación como `Date` no dependa de dónde corra
    /// el proceso: con `Europe/Madrid` (UTC+1/+2), la medianoche local cae el día
    /// **anterior** en UTC y el 1 de julio se guardaría como 30 de junio.
    ///
    /// No contradice el `Europe/Madrid` que pide el [Anexo RFFM §F.11]: ése es
    /// para los **instantes** sin huso de la federación (`fecha`, hora de
    /// partido), no para una fecha de calendario derivada de una etiqueta.
    private static func day(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Inalcanzable: los tres componentes están fijados y el calendario es
        // gregoriano, así que la fecha siempre existe.
        return calendar.date(from: components)!
    }
}
