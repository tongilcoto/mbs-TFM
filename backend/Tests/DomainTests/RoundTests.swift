import Foundation
import Testing

@testable import Domain

/// Nivel 1 (§8.1): la jornada y de dónde salen sus dos fechas.
@Suite("Round · §3.2 · la jornada de la competición")
struct RoundTests {

    static func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "Europe/Madrid")
        f.dateFormat = "dd-MM-yyyy"
        return f.date(from: iso)!
    }

    /// §3.2: `start_date` y `end_date` son un **rango**, y un rango al revés no
    /// es un rango. No lo puede impedir el esquema —son dos columnas sueltas—,
    /// así que lo impide el tipo.
    @Test("una jornada que acaba antes de empezar no es una jornada (§3.2)")
    func rejectsInvertedSpan() throws {
        #expect(throws: DomainError.self) {
            try Round(
                id: RoundID(raw: UUID()),
                competitionID: CompetitionID(raw: UUID()),
                number: 1,
                startDate: Self.date("28-09-2025"),
                endDate: Self.date("27-09-2025"),
                createdAt: Date(),
                updatedAt: Date()
            )
        }
    }

    /// §3.5 la hace parte de la clave única (competición, número), y §F.15 la
    /// saca de `codjornada`. Un cero o un negativo solo puede venir de un
    /// `codjornada` que dejó de ser lo que era, y eso hay que verlo aquí y no
    /// en un `UNIQUE` que lo aceptaría tan contento.
    @Test("el número de jornada no puede ser cero ni negativo (§3.5)")
    func rejectsNonPositiveNumber() throws {
        #expect(throws: DomainError.self) {
            try Round(
                id: RoundID(raw: UUID()),
                competitionID: CompetitionID(raw: UUID()),
                number: 0,
                startDate: Self.date("27-09-2025"),
                endDate: Self.date("28-09-2025"),
                createdAt: Date(),
                updatedAt: Date()
            )
        }
    }

    // ── El rango de la jornada (D-81) ────────────────────────────────────────

    /// `D-81`: la federación **no publica** ni `start_date` ni `end_date`. Lo
    /// único que hay es la fecha de cada partido, así que el rango se deriva de
    /// ellas — mínimo y máximo, sin más.
    ///
    /// El caso está tomado del volcado de temporada jugada: la jornada 1 reparte
    /// partidos entre el sábado 27 y el domingo 28, y la temporada tiene además
    /// 4 partidos entre semana. **La lista llega desordenada a propósito**: es lo
    /// que distingue "mínimo" de "el primero".
    @Test("el rango de la jornada es el mínimo y el máximo de sus partidos (D-81)")
    func spanIsMinAndMaxOfMatchDates() throws {
        let span = Round.span(ofMatchDates: [
            Self.date("28-09-2025"), Self.date("27-09-2025"), Self.date("01-10-2025"),
        ])

        #expect(span == Self.date("27-09-2025")...Self.date("01-10-2025"))
    }

    /// La otra mitad de `D-81`, y **llegó en verde**: la misma línea que calcula
    /// el mínimo y el máximo produce esto sin una rama propia. Se escribe igual
    /// porque es la decisión que se tomó —y la que un futuro "mejor pongamos el
    /// fin de semana entero" tumbaría—, no porque hiciera falta un ciclo.
    ///
    /// Es el caso del volcado de temporada **sin arrancar**: sus 306 partidos
    /// comparten una sola fecha, así que la jornada dura un día. Escribir ahí un
    /// sábado que la federación no ha dicho sería inventar dato, que es
    /// justamente lo que `D-75` prohíbe.
    @Test("una jornada sin arrancar dura un solo día, no un fin de semana (D-81)")
    func spanCollapsesWhenAllMatchesShareADate() throws {
        let sunday = Self.date("13-09-2026")
        let span = Round.span(ofMatchDates: [sunday, sunday, sunday])

        #expect(span == sunday...sunday)
    }

    // ── El rango es volátil (§3.7) ───────────────────────────────────────────

    static func round(_ start: String, _ end: String) throws -> Round {
        try Round(
            id: RoundID(raw: UUID()),
            competitionID: CompetitionID(raw: UUID()),
            number: 1,
            startDate: Self.date(start),
            endDate: Self.date(end),
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// §3.7, clase **volátil**: el rango es propiedad de la federación, igual
    /// que la fecha de los partidos de los que sale. Un partido aplazado al
    /// miércoles estira la jornada, y la pasada siguiente tiene que reflejarlo.
    @Test("la jornada que se mueve actualiza su rango (§3.7, volátil)")
    func spanIsOverwrittenWhenTheSourceSpeaks() throws {
        let existing = try Self.round("27-09-2025", "28-09-2025")

        let merged = existing.merging(
            span: Self.date("27-09-2025")...Self.date("01-10-2025"))

        #expect(merged.startDate == Self.date("27-09-2025"))
        #expect(merged.endDate == Self.date("01-10-2025"))
    }

    /// La otra fila de `D-56`, y **llegó en verde**: no hay rama que la
    /// implemente porque **no se puede escribir el fallo**. `startDate` y
    /// `endDate` son `NOT NULL` (§3.2), así que "pisar siempre" exigiría
    /// inventarse una fecha centinela — la firma no lo permite. Es el mismo
    /// argumento estructural con el que `MatchCandidate` no lleva fecha (F4).
    @Test("una pasada sin fechas no borra el rango que había (D-56)")
    func spanSurvivesASilentPass() throws {
        let existing = try Self.round("27-09-2025", "28-09-2025")

        let merged = existing.merging(span: nil)

        #expect(merged.startDate == Self.date("27-09-2025"))
        #expect(merged.endDate == Self.date("28-09-2025"))
    }
}
