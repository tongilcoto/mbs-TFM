import Testing
@testable import Domain

/// Nivel 1 (§8.1): el nombre del jugador (`D-120`), **cero I/O**.
///
/// La regla es la misma en el alta, la corrección y la sincronización, y por eso
/// vive aquí y no en el catálogo: la sincronización no pasa por él.
@Suite("PlayerName · D-120 · limpio, en mayúsculas y con al menos dos palabras")
struct PlayerNameTests {

    // ── «El mismo nombre», para casar la sincronización (D-120, R6.3) ──

    /// Igual una vez en mayúsculas, con un solo espacio entre palabras y **sin tildes ni diéresis**; **la eñe
    /// cuenta como letra distinta**, lo eligió el desarrollador. Las dos primeras ya las pone `PlayerName`.
    @Test("el mismo nombre: sin contar tildes ni diéresis", arguments: [
        ("José García", "JOSE GARCIA"), ("Íñigo Argüelles", "IÑIGO ARGUELLES"), ("ÁLVARO ÓSCAR", "alvaro oscar"),
    ])
    func sameNameIgnoresAccents(_ a: String, _ b: String) throws {
        #expect(try PlayerName(a).sameNameKey == PlayerName(b).sameNameKey)
    }

    @Test("no es el mismo nombre: la eñe, otra letra, o un guion en vez de un espacio", arguments: [
        ("Juan Muñoz", "Juan Munoz"), ("Juan García", "Juan Garcías"), ("Ana Pérez-Gil", "Ana Pérez Gil"),
    ])
    func sameNameKeepsTheRest(_ a: String, _ b: String) throws {
        #expect(try PlayerName(a).sameNameKey != PlayerName(b).sameNameKey)
    }

    @Test("se guarda en mayúsculas, también la eñe y las tildes")
    func uppercases() throws {
        #expect(try PlayerName("José Muñoz").value == "JOSÉ MUÑOZ")
        #expect(try PlayerName("lucía güell").value == "LUCÍA GÜELL")
    }

    @Test("se limpian los espacios: fuera los de los bordes y uno solo entre palabras")
    func cleansSpaces() throws {
        #expect(try PlayerName("  juan   garcía \t fuente  ").value == "JUAN GARCÍA FUENTE")
    }

    /// Una tilde escrita como dos piezas (la letra y el acento aparte), que es
    /// como la mandan algunos teclados, se guarda igual que la de una pieza: si
    /// no, «José» serían dos nombres distintos en la base.
    @Test("una tilde en dos piezas se guarda como la de una")
    func composesAccents() throws {
        let decomposed = "Jose\u{301} Pe\u{301}rez"
        #expect(try PlayerName(decomposed).value == "JOSÉ PÉREZ")
    }

    @Test("admite guion y apóstrofo dentro de una palabra", arguments: [
        ("Ana Pérez-Gil", "ANA PÉREZ-GIL"),
        ("Liam O'Brien", "LIAM O'BRIEN"),
        ("Marc d’Ors", "MARC D’ORS"),
    ])
    func acceptsHyphenAndApostrophe(_ raw: String, _ stored: String) throws {
        #expect(try PlayerName(raw).value == stored)
    }

    @Test("los 120 caracteres justos valen")
    func acceptsTheLimit() throws {
        let raw = "A " + String(repeating: "B", count: 118)
        #expect(try PlayerName(raw).value.count == 120)
    }

    /// Los cinco casos de `plantilla-federacion.feature`, y dos más que la regla
    /// pide: una palabra sin letras y el apellido de una sola letra suelta.
    @Test("rechaza lo que no vale, con el campo y un motivo para el usuario", arguments: [
        "",                                         // vacío
        "   ",                                      // solo espacios
        "Juan",                                     // una sola palabra
        "Juan García 2",                            // con un número
        "Juan García!",                             // con un símbolo
        "Juan " + String(repeating: "B", count: 116),  // 121 caracteres
        "Juan -",                                   // una palabra sin letras
        "Juan '",                                   // ídem, con apóstrofo
    ])
    func rejects(_ raw: String) {
        #expect {
            try PlayerName(raw)
        } throws: { error in
            guard case DomainError.invalidValue(let field, let reason) = error else { return false }
            return field == "fullName" && !reason.isEmpty
        }
    }

    @Test("cada motivo dice qué falla", arguments: [
        ("", "no puede estar vacío"),
        ("Juan", "el nombre y al menos un apellido"),
        ("Juan García 2", "solo puede llevar letras"),
        ("Juan " + String(repeating: "B", count: 116), "120"),
        ("Juan -", "cada palabra tiene que llevar letras"),
    ])
    func reasons(_ raw: String, _ fragment: String) {
        #expect {
            try PlayerName(raw)
        } throws: { error in
            guard case DomainError.invalidValue(_, let reason) = error else { return false }
            return reason.contains(fragment)
        }
    }
}
