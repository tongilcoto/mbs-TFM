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

    /// §3.2: la vigente es la de `endDate` **más próximo que aún es ≥ hoy**.
    @Test("la temporada vigente es la de fin más próximo aún no pasado (§3.2)")
    func currentIsTheNearestNotYetEnded() throws {
        let seasons = [
            try Self.make("2023/24"),  // acabó el 2024-06-30
            try Self.make("2024/25"),  // acabó el 2025-06-30
            try Self.make("2025/26"),  // acaba  el 2026-06-30
            try Self.make("2026/27"),  // acaba  el 2027-06-30
        ]
        let enero2026 = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01

        #expect(seasons.current(on: enero2026)?.label.value == "2025/26")
    }

    /// El corte es **inclusivo**: el 30 de junio la temporada sigue siendo la
    /// vigente; el 1 de julio ya lo es la siguiente. Como el tiempo no retrocede,
    /// hay exactamente una y no queda invariante que mantener.
    @Test("el último día de la temporada aún es el suyo (§3.2)")
    func theLastDayStillCounts() throws {
        let seasons = [try Self.make("2025/26"), try Self.make("2026/27")]
        let label = try SeasonLabel("2025/26")

        #expect(seasons.current(on: label.endDate)?.label.value == "2025/26")
        #expect(seasons.current(on: label.endDate.addingTimeInterval(86_400))?
            .label.value == "2026/27")
    }

    /// Archivar oculta la temporada (§3.5). Una temporada oculta que resultara
    /// ser la vigente dejaría al cliente sin ninguna.
    @Test("una temporada archivada no puede ser la vigente (§3.5)")
    func archivedSeasonsAreNeverCurrent() throws {
        let vigente = try Self.make("2025/26")
        let seasons = [
            try vigente.archived(at: Date(timeIntervalSince1970: 0)),
            try Self.make("2026/27"),
        ]
        let enero2026 = Date(timeIntervalSince1970: 1_767_225_600)

        #expect(seasons.current(on: enero2026)?.label.value == "2026/27")
    }

    /// Con todas pasadas no hay vigente, y eso es un resultado, no un fallo.
    @Test("sin ninguna temporada en curso, no hay vigente (§3.2)")
    func noCurrentSeasonIsAValidAnswer() throws {
        let seasons = [try Self.make("2023/24")]
        let enero2026 = Date(timeIntervalSince1970: 1_767_225_600)

        #expect(seasons.current(on: enero2026) == nil)
        #expect([Season]().current(on: enero2026) == nil)
    }
}
