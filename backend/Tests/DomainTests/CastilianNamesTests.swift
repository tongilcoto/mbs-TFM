import Testing
@testable import Domain

/// Nivel 1 (§8.1): el diccionario de nombres y apellidos en castellano (`D-123`), **cero I/O**.
@Suite("CastilianNames · D-123 · las tildes y eñes que quita la federación")
struct CastilianNamesTests {

    static let all = CastilianNames.givenNames + CastilianNames.surnames

    // ── La lista ──

    /// Solo hacen falta las palabras con tilde, eñe o diéresis: las demás ya llegan bien.
    @Test("cada palabra de la lista lleva su tilde, eñe o diéresis")
    func everyWordHasItsMark() {
        let unmarked = Self.all.filter { PlayerSearch.fold($0) == $0 }
        #expect(unmarked.isEmpty, "\(unmarked)")
    }

    /// Una sola forma por palabra: dos que se buscan igual dirían cosas distintas.
    @Test("ninguna palabra está dos veces, ni con otras tildes")
    func noWordTwice() {
        let keys = Self.all.map(PlayerSearch.fold)
        let repeated = Set(keys.filter { key in keys.filter { $0 == key }.count > 1 })
        #expect(repeated.isEmpty, "\(repeated)")
    }

    /// En mayúsculas, sin espacios: se busca palabra a palabra.
    @Test("cada palabra, en mayúsculas y sola")
    func everyWordUppercaseAndAlone() {
        let wrong = Self.all.filter { $0 != $0.uppercased() || $0.contains(" ") || $0.contains("-") }
        #expect(wrong.isEmpty, "\(wrong)")
    }

    /// Las que existen de las dos maneras, decididas con el desarrollador (R6.17).
    @Test("de las dudosas, entran Díez, Sáez, Martí, Mía y Éric; Saiz, Zoe e Iker, no")
    func doubtfulDecided() throws {
        for (raw, spelled) in [("JORGE DIEZ", "JORGE DÍEZ"), ("JORGE SAEZ", "JORGE SÁEZ"), ("JORGE MARTI", "JORGE MARTÍ"),
                               ("MIA PEREZ", "MÍA PÉREZ"), ("ERIC GIL", "ÉRIC GIL"), ("JORGE SAIZ", "JORGE SAIZ"),
                               ("ZOE GIL", "ZOE GIL"), ("IKER GIL", "IKER GIL")] {
            #expect(try PlayerName(raw).spelledInCastilian().value == spelled)
        }
    }

    // ── Aplicarla a un nombre ──

    @Test("pone las tildes, las eñes y las diéresis que faltan", arguments: [
        ("JORGE FERNANDEZ PEREZ", "JORGE FERNÁNDEZ PÉREZ"),
        ("JESUS MUNOZ IBANEZ", "JESÚS MUÑOZ IBÁÑEZ"),
        ("ROMAN MARTIN ARGUELLES", "ROMÁN MARTÍN ARGÜELLES"),
    ])
    func addsMarks(_ raw: String, _ spelled: String) throws {
        #expect(try PlayerName(raw).spelledInCastilian().value == spelled)
    }

    @Test("lo que no está en la lista, y lo que ya llega bien, se queda como está")
    func leavesTheRest() throws {
        #expect(try PlayerName("JORGE RUIZ SANZ").spelledInCastilian().value == "JORGE RUIZ SANZ")
        #expect(try PlayerName("JORGE GARCÍA").spelledInCastilian().value == "JORGE GARCÍA")
        #expect(try PlayerName("KEVIN SMITH").spelledInCastilian().value == "KEVIN SMITH")
    }

    /// Solo palabras enteras: «PEREZOSO» no es «PÉREZ», y «MARTINEZ» no se toca por «MARTÍN».
    @Test("solo palabras enteras, también tras un guion")
    func wholeWordsOnly() throws {
        #expect(try PlayerName("JORGE GARCIA-PEREZ").spelledInCastilian().value == "JORGE GARCÍA-PÉREZ")
        #expect(try PlayerName("JORGE PEREZOSO").spelledInCastilian().value == "JORGE PEREZOSO")
        #expect(try PlayerName("JORGE O'MARTIN").spelledInCastilian().value == "JORGE O'MARTIN")
    }

    /// Escrito con otras tildes, se corrige a la de la lista: «LOPÉZ» es «LÓPEZ».
    @Test("una tilde mal puesta se cambia por la de la lista")
    func wrongMarkIsReplaced() throws {
        #expect(try PlayerName("JORGE LOPÉZ").spelledInCastilian().value == "JORGE LÓPEZ")
    }
}
