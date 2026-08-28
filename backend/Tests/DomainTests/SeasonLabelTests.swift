import Foundation
import Testing
@testable import Domain

/// Nivel 1 de la pirámide (§8.1): invariantes de *Value Objects*, **cero I/O**.
@Suite("SeasonLabel · §4.1 · el formato del modelo y las fechas que se derivan de él")
struct SeasonLabelTests {

    @Test("acepta AAAA/AB con años consecutivos", arguments: [
        "2024/25", "2025/26", "1999/00", "2099/00", "2000/01",
    ])
    func acceptsConsecutiveYears(_ value: String) throws {
        #expect(try SeasonLabel(value).value == value)
    }

    /// Los cinco primeros los rechaza también el `pattern` del *spec*
    /// (`^\d{4}/\d{2}$`); los tres últimos **no**, y son el motivo de `D-71`.
    @Test("rechaza lo que el pattern rechaza", arguments: [
        "",           // vacío
        "2024-25",    // separador de la RFFM, no el del modelo
        "2024/2025",  // año completo en la segunda mitad
        "24/25",      // año corto en la primera
        "abcd/ef",    // no dígitos
    ])
    func rejectsMalformed(_ value: String) {
        #expect(throws: DomainError.self) { try SeasonLabel(value) }
    }

    /// **El test que justifica `D-71`.** Los tres cumplen `^\d{4}/\d{2}$` y los
    /// tres son imposibles. `"2025/20"` es literalmente lo que produce un
    /// reformateo mal escrito de `"2025-2026"` (Anexo RFFM §F.11) — el fallo que
    /// la ruta de ingesta no tiene quién le pare, porque no pasa por el contrato.
    @Test("rechaza lo que el pattern deja pasar: los dos años no son consecutivos", arguments: [
        "2025/20",  // los dos caracteres equivocados de "2025-2026"
        "2024/99",  // incoherente sin más
        "2024/24",  // el mismo año dos veces
        "2024/26",  // se salta uno
    ])
    func rejectsIncoherentYears(_ value: String) {
        #expect(throws: DomainError.self) { try SeasonLabel(value) }
    }

    /// §3.2: `start_date`/`end_date` **fijas y derivadas de `label`**, 01/07/AAAA
    /// → 30/06/AABB, y **no *overridables***.
    @Test("deriva el 1 de julio y el 30 de junio del año siguiente (§3.2)")
    func derivesFixedDates() throws {
        let label = try SeasonLabel("2025/26")

        #expect(label.startYear == 2025)
        #expect(label.endYear == 2026)
        #expect(Self.utc(label.startDate) == "2025-07-01")
        #expect(Self.utc(label.endDate) == "2026-06-30")
    }

    /// El cambio de siglo es el caso que un `+ 1` sobre dos dígitos rompe.
    @Test("el cambio de siglo se deriva igual (2099/00)")
    func derivesAcrossCenturies() throws {
        let label = try SeasonLabel("2099/00")

        #expect(label.endYear == 2100)
        #expect(Self.utc(label.startDate) == "2099-07-01")
        #expect(Self.utc(label.endDate) == "2100-06-30")
    }

    /// Las dos son fechas de calendario, no instantes: se construyen en UTC para
    /// que la representación no dependa de dónde corra el proceso. Con
    /// `Europe/Madrid` el 1 de julio se guardaría como 30 de junio.
    @Test("las fechas derivadas no dependen del huso del proceso (§4.1)")
    func derivedDatesAreTimeZoneIndependent() throws {
        let label = try SeasonLabel("2025/26")
        // Medianoche UTC exacta: si se hubiera construido en hora local, el
        // instante no caería en el segundo cero del día.
        #expect(label.startDate.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400) == 0)
    }

    private static func utc(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
