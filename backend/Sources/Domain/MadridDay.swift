import struct Foundation.Calendar
import struct Foundation.Date
import struct Foundation.TimeZone

/// **El día de Madrid en que cae un instante**, escrito como lo están las fechas
/// sin hora del dominio: a las 00:00 en UTC (`SeasonLabel`, `Round`). Es con lo
/// que se comparan «hoy» y esas fechas, por días y no por instantes: lo usan
/// `Season.current(on:)` y `Round.current(on:)`.
enum MadridDay {
    static func of(_ instant: Date) -> Date {
        var madrid = Calendar(identifier: .gregorian)
        madrid.timeZone = TimeZone(identifier: "Europe/Madrid")!
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        // Inalcanzable: año, mes y día salen de una fecha que existe.
        return utc.date(from: madrid.dateComponents([.year, .month, .day], from: instant))!
    }
}
