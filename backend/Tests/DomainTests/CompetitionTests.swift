import Foundation
import Testing
@testable import Domain

/// Nivel 1 (§8.1): la guarda de mutabilidad de `D-22`/`D-58` y el rótulo
/// derivado, **cero I/O**. Es la regla más delicada que entrega F1.
@Suite("Competition · D-22 · lo que se sincronizó deja de ser editable")
struct CompetitionTests {

    static func make(lastSyncedAt: Date? = nil, federationName: String? = nil) throws -> Competition {
        try Competition(
            id: CompetitionID(raw: UUID()),
            seasonID: SeasonID(raw: UUID()),
            modality: .futbol11,
            gender: .masculino,
            federationCompetitionID: "24037548",
            federationGroupID: "24037549",
            ageCategory: .infantil,
            divisionLabel: "Primera",
            groupLabel: "Grupo 1",
            federationName: federationName,
            lastSyncedAt: lastSyncedAt,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    static let sincronizada = Date(timeIntervalSince1970: 1_000)

    // ── Invariantes de alta ──────────────────────────────────────────────────

    /// §3.2: las dos coordenadas son **obligatorias**, y los rótulos texto libre
    /// pero no vacío (`minLength: 1` del *spec*, que el generador ignora, `D-65`).
    @Test("ni las coordenadas ni los rótulos pueden venir vacíos (§3.2)")
    func rejectsEmptyRequiredText() throws {
        let base = try Self.make()

        #expect(throws: DomainError.self) { try base.applying(divisionLabel: "") }
        #expect(throws: DomainError.self) { try base.applying(groupLabel: "  ") }
        #expect(throws: DomainError.self) { try base.applying(federationCompetitionID: "") }
    }

    /// §5.2: derivado de los **tres rótulos nuestros**, no del nombre que publica
    /// la federación — que llega truncado a 40 caracteres (Anexo RFFM §F.11).
    @Test("displayName se compone de los tres rótulos, no hay columna (§5.2)")
    func displayNameIsDerived() throws {
        let competition = try Self.make(federationName: "INFANTIL PRIMERA DIVISION GRUPO 1")

        #expect(competition.displayName == "Infantil · Primera · Grupo 1")
    }

    // ── La guarda de D-22 ────────────────────────────────────────────────────

    /// Antes de la primera sincronización todo se puede corregir: es justo la
    /// ventana en que un dígito mal copiado (`D-16`) todavía tiene arreglo.
    @Test("sin sincronizar, las coordenadas y el género sí se editan (§3.7)")
    func everythingIsEditableBeforeFirstSync() throws {
        let competition = try Self.make(lastSyncedAt: nil)
        #expect(!competition.isSynced)

        let updated = try competition.applying(
            gender: .femenino,
            federationCompetitionID: "99999999",
            federationGroupID: "88888888"
        )

        #expect(updated.gender == .femenino)
        #expect(updated.federationCompetitionID == "99999999")
        #expect(updated.federationGroupID == "88888888")
    }

    /// Cambiar una coordenada con datos ya colgando es **repuntar a otro
    /// calendario**. El adaptador lo traducirá a 409, no a 422 (§5.4).
    @Test("sincronizada, cambiar una coordenada se rechaza (D-22)")
    func coordinatesFreezeAfterSync() throws {
        let competition = try Self.make(lastSyncedAt: Self.sincronizada)
        #expect(competition.isSynced)

        #expect(throws: DomainError.notEditableAfterSync(field: "federationCompetitionId")) {
            try competition.applying(federationCompetitionID: "99999999")
        }
        #expect(throws: DomainError.notEditableAfterSync(field: "federationGroupId")) {
            try competition.applying(federationGroupID: "88888888")
        }
    }

    /// **`gender` sigue la regla de las coordenadas y es el único campo no
    /// coordenada que lo hace** (`D-58`): ya se propagó a cada `Team` que creó la
    /// ingesta, donde entra en la clave única (§3.5). Cambiarlo después dejaría
    /// la competición diciendo una cosa y sus equipos otra.
    @Test("sincronizada, el género tampoco se edita — y ése es todo D-58")
    func genderFreezesAfterSyncToo() throws {
        let competition = try Self.make(lastSyncedAt: Self.sincronizada)

        #expect(throws: DomainError.notEditableAfterSync(field: "gender")) {
            try competition.applying(gender: .femenino)
        }
    }

    /// La otra mitad de la regla, y la que evita que la guarda se lea como
    /// "sincronizada = congelada": los rótulos **solo se muestran**, así que
    /// corregir una errata sigue siendo posible para siempre.
    @Test("sincronizada, los rótulos se siguen editando (§3.7)")
    func labelsStayEditableAfterSync() throws {
        let competition = try Self.make(lastSyncedAt: Self.sincronizada)

        let updated = try competition.applying(
            ageCategory: .cadete, divisionLabel: "Preferente", groupLabel: "Grupo Único")

        #expect(updated.displayName == "Cadete · Preferente · Grupo Único")
        #expect(updated.isSynced, "corregir un rótulo no deshace la sincronización")
    }

    /// Reenviar el mismo valor no es un cambio. Sin esto, un `PATCH` que repite
    /// el cuerpo entero —lo normal en un formulario de backoffice— daría 409 sin
    /// haber pedido modificar nada.
    @Test("reenviar el mismo valor no es un cambio, así que no da conflicto (§5.5)")
    func resendingTheSameValueIsNotAChange() throws {
        let competition = try Self.make(lastSyncedAt: Self.sincronizada)

        let updated = try competition.applying(
            gender: .masculino,                    // el que ya tiene
            divisionLabel: "Segunda",               // esto sí cambia
            federationCompetitionID: "24037548"     // el que ya tiene
        )

        #expect(updated.divisionLabel == "Segunda")
    }

    /// `D-72`: es **evidencia, no rótulo**. No lo escribe un `PATCH` — lo pone la
    /// ingesta, que es quien lo lee de la federación.
    @Test("federationName no viaja en el PATCH: lo escribe la ingesta (D-72)")
    func federationNameIsNotPatchable() throws {
        let competition = try Self.make(federationName: "TERCERA FEDERACION DE FÚTBOL FEMENINO")

        let updated = try competition.applying(divisionLabel: "Segunda")

        #expect(updated.federationName == "TERCERA FEDERACION DE FÚTBOL FEMENINO")
    }
}
