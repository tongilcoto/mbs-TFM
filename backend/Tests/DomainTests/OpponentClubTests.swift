import Foundation
import Testing

@testable import Domain

/// Nivel 1 (§8.1): el club rival y su política de *upsert* (§3.7).
@Suite("OpponentClub · §3.7 · lo que la ingesta puede y no puede reescribir")
struct OpponentClubTests {

    static func club(
        name: String = "CELTIC CASTILLA C.F.",
        shortName: String = "CELTIC CASTILLA C.F.",
        federationClubID: String? = nil,
        crestKey: String? = nil
    ) throws -> OpponentClub {
        try OpponentClub(
            id: OpponentClubID(raw: UUID()),
            name: name,
            shortName: shortName,
            slug: try Slug(derivedFrom: name),
            federationClubID: federationClubID,
            crestKey: crestKey,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // ── Descriptivo: la fuente siembra y no vuelve a tocar (§3.7) ────────────

    /// §3.7, clase **descriptiva**: `name` se escribe *solo en el INSERT*. La
    /// fuente lo publica en mayúsculas y el administrador lo arregla; si la
    /// pasada del lunes lo volviera a pisar, la corrección duraría una semana —
    /// y el `PATCH` sería tan poco duradero como un `DELETE` (`D-21`).
    @Test("la corrección del nombre sobrevive a la pasada siguiente (§3.7, descriptivo)")
    func nameIsNotOverwritten() throws {
        let corrected = try Self.club(name: "Celtic Castilla C.F.")

        let merged = try corrected.merging(
            name: "CELTIC CASTILLA C.F.", shortName: nil,
            crestKey: nil, federationClubID: nil)

        #expect(merged.name == "Celtic Castilla C.F.")
    }

    /// Misma clase, y hace falta su propio test: `shortName` es el que se
    /// muestra, así que es **el que el administrador corrige primero**.
    @Test("el nombre corto corregido tampoco se pisa (§3.7, descriptivo)")
    func shortNameIsNotOverwritten() throws {
        let corrected = try Self.club(shortName: "Celtic Castilla")

        let merged = try corrected.merging(
            name: nil, shortName: "CELTIC CASTILLA C.F.",
            crestKey: nil, federationClubID: nil)

        #expect(merged.shortName == "Celtic Castilla")
    }

    /// Misma clase, tercera pieza (§3.7). Hoy `crestKey` nace nulo porque F5 no
    /// trae Storage, pero su regla se decide igual: cuando el escudo se descargue
    /// (`D-19`), un club que cambie de escudo **no** debe perder la clave que ya
    /// apunta a un objeto subido.
    @Test("la clave del escudo no la reescribe la ingesta (§3.7, descriptivo)")
    func crestKeyIsNotOverwritten() throws {
        let stored = try Self.club(crestKey: "clubs/celtic-castilla-c-f/crest.png")

        let merged = try stored.merging(
            name: nil, shortName: nil,
            crestKey: "clubs/otro/crest.png", federationClubID: nil)

        #expect(merged.crestKey == "clubs/celtic-castilla-c-f/crest.png")
    }

    // ── De emparejamiento: no sobrescribe, pero rellena hueco (§3.7) ─────────

    /// §3.7: las claves de salida son **inmutables**. Si la federación
    /// renumerase, se degrada el emparejamiento, no la integridad — y el arreglo
    /// es la fusión de §9, no un `UPDATE` que pise la clave con la que la fila
    /// se venía reconociendo.
    @Test("una clave de federación distinta no reescribe la que ya había (§3.7)")
    func federationKeyIsNotOverwritten() throws {
        let matched = try Self.club(federationClubID: "0010940034")

        let merged = try matched.merging(
            name: nil, shortName: nil, crestKey: nil, federationClubID: "0011078749")

        #expect(merged.federationClubID == "0010940034")
    }

    /// `D-76`, la otra mitad: la fila que nació sin clave —porque la inferencia
    /// sobre el nombre del fichero del escudo falló ([Anexo RFFM §F.4])— **la
    /// recibe** el día que la fuente la publique. Sin esto se quedaría
    /// emparejándose por nombre para siempre, que es el paso inexacto.
    ///
    /// Llega en verde contra el esqueleto y se escribe igual: es la mitad del
    /// par que hace que la regla no sea "no toques nunca".
    @Test("una fila sin clave la recibe cuando la fuente la publica (D-76)")
    func federationKeyFillsTheGap() throws {
        let unmatched = try Self.club(federationClubID: nil)

        let merged = try unmatched.merging(
            name: nil, shortName: nil, crestKey: nil, federationClubID: "0010940034")

        #expect(merged.federationClubID == "0010940034")
    }
}
