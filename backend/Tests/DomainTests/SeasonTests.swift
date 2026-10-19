import Foundation
import Testing
@testable import Domain

/// Nivel 1 (§8.1): reglas de la entidad, **cero I/O**.
@Suite("Season · §3.2 · archivar no es borrar, y la vigente se deriva")
struct SeasonTests {

    static func make(
        _ label: String, federationSeasonID: String = "21", archivedAt: Date? = nil
    ) throws -> Season {
        try Season(
            id: SeasonID(raw: UUID()),
            label: try SeasonLabel(label),
            federationSeasonID: federationSeasonID,
            archivedAt: archivedAt,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// §3.2: **obligatorio**, toda temporada tiene contrapartida en la federación.
    @Test("el federationSeasonId es obligatorio y no puede venir vacío (§3.2)")
    func requiresFederationSeasonID() {
        #expect(throws: DomainError.self) { try Self.make("2025/26", federationSeasonID: "") }
        #expect(throws: DomainError.self) { try Self.make("2025/26", federationSeasonID: "   ") }
    }

    /// §3.2: las dos fechas son **derivadas de `label`**, así que no hay forma de
    /// escribirlas desalineadas — ni siquiera desde dentro del propio dominio.
    @Test("las fechas salen de la etiqueta, no de un campo aparte (§3.2)")
    func datesFollowTheLabel() throws {
        let season = try Self.make("2025/26")

        #expect(season.startDate == season.label.startDate)
        #expect(season.endDate == season.label.endDate)

        // Y siguen a la etiqueta cuando cambia: no hay copia que se quede atrás.
        let siguiente = try SeasonLabel("2026/27")
        let renamed = try season.applying(label: siguiente)
        #expect(renamed.endDate == siguiente.endDate)
    }

    /// §3.5: `archived_at` es archivado **reversible**, deliberadamente distinto
    /// del *soft delete* — `Season` sí admite borrado físico, que es otra cosa.
    @Test("archivar y restaurar es reversible, y no es borrar (§3.5)")
    func archivingIsReversible() throws {
        let season = try Self.make("2025/26")
        #expect(!season.isArchived)

        let archived = try season.archived(at: Date(timeIntervalSince1970: 1_000))
        #expect(archived.isArchived)
        #expect(archived.id == season.id, "archivar no cambia la identidad")

        let restored = try archived.restored()
        #expect(!restored.isArchived)
    }

    /// §5.5: campo ausente = no se modifica. Y `archivedAt` **no** viaja en el
    /// PATCH: se cambia con `archive`/`restore`, que son sus propias operaciones.
    @Test("el PATCH parcial no toca lo que no le pasan (§5.5)")
    func patchLeavesAbsentFieldsAlone() throws {
        let season = try Self.make("2025/26", federationSeasonID: "21")
        let archived = try season.archived(at: Date(timeIntervalSince1970: 1_000))

        let updated = try archived.applying(federationSeasonID: "22")

        #expect(updated.federationSeasonID == "22")
        #expect(updated.label == season.label, "no se pasó label, no se toca")
        #expect(updated.isArchived, "archivedAt no es campo de PATCH")
    }

    /// Un instante en UTC, para escribir las horas de los tests sin ambigüedad.
    static func utc(_ text: String) -> Date {
        try! Date(text, strategy: .iso8601)
    }

    /// §3.2 (Plan R1, decisión 5): **en curso es la que contiene el día de hoy**,
    /// del 1 de julio al 30 de junio.
    @Test("la temporada en curso es la que contiene el día de hoy (§3.2)")
    func currentIsTheOneContainingToday() throws {
        let seasons = [
            try Self.make("2024/25"),
            try Self.make("2025/26"),
            try Self.make("2026/27"),
        ]

        #expect(seasons.current(on: Self.utc("2026-01-15T12:00:00Z"))?.label.value == "2025/26")
    }

    /// El caso en que la regla vieja (*"`endDate` más próximo que aún es ≥ hoy"*)
    /// fallaba: sin la del año creada, una temporada creada por adelantado salía
    /// en curso meses antes de empezar. Y la web no podía decir *"todavía no ha
    /// empezado"* (Plan R1, decisión 5).
    @Test("una temporada creada por adelantado no está en curso antes de su 1 de julio")
    func aSeasonCreatedInAdvanceIsNotCurrentYet() throws {
        let seasons = [try Self.make("2025/26"), try Self.make("2027/28")]

        #expect(seasons.current(on: Self.utc("2026-10-18T12:00:00Z")) == nil)
    }

    /// El corte es **por días y en hora de Madrid**: el 30 de junio, a cualquier
    /// hora, la temporada sigue siendo la suya. La regla vieja comparaba el
    /// instante con las 00:00 del 30 de junio, y a mediodía ya daba la siguiente.
    @Test("el 30 de junio, hasta las 23:59 de Madrid, sigue siendo de la temporada que acaba")
    func theWholeLastDayCounts() throws {
        let seasons = [try Self.make("2025/26"), try Self.make("2026/27")]

        // 23:30 en Madrid (UTC+2 en verano).
        #expect(seasons.current(on: Self.utc("2026-06-30T21:30:00Z"))?.label.value == "2025/26")
    }

    /// El día es el de Madrid, no el de UTC: a las 00:30 del 1 de julio en Madrid
    /// todavía es 30 de junio en UTC, y la temporada ya es la nueva.
    @Test("el 1 de julio de Madrid ya es de la temporada nueva, aunque en UTC sea 30 de junio")
    func theDayIsCountedInMadrid() throws {
        let seasons = [try Self.make("2025/26"), try Self.make("2026/27")]

        #expect(seasons.current(on: Self.utc("2026-06-30T22:30:00Z"))?.label.value == "2026/27")
    }

    /// Archivar oculta la temporada (§3.5). Una temporada oculta no está en curso.
    @Test("una temporada archivada no está en curso (§3.5)")
    func archivedSeasonsAreNeverCurrent() throws {
        let seasons = [
            try Self.make("2025/26").archived(at: Date(timeIntervalSince1970: 0)),
            try Self.make("2026/27"),
        ]

        #expect(seasons.current(on: Self.utc("2026-01-15T12:00:00Z")) == nil)
    }

    /// Sin ninguna en curso no hay vigente, y eso es un resultado, no un fallo:
    /// es julio antes de crear la del año.
    @Test("sin ninguna temporada en curso, no hay vigente (§3.2)")
    func noCurrentSeasonIsAValidAnswer() throws {
        let seasons = [try Self.make("2025/26")]

        #expect(seasons.current(on: Self.utc("2026-08-01T12:00:00Z")) == nil)
        #expect([Season]().current(on: Self.utc("2026-08-01T12:00:00Z")) == nil)
    }
}
